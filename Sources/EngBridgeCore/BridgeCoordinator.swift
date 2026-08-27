import EngCore
import Foundation
@preconcurrency import MultipeerConnectivity

public actor BridgeCoordinator {
  private let nearby: NearbyServer
  private let service: CodexThreadService
  private let telemetry: MacTelemetrySampler
  private let bridgeName: String
  private var pairingGate: PairingGate
  private var pairedPeers = Set<String>()
  private var peerDevices: [String: UUID] = [:]
  private var subscriptions: [String: String] = [:]
  private var phoneAnalytics: [String: AnalyticsSnapshot] = [:]
  private var lastWorkspace: WorkspaceSnapshot?
  private var lastMacTelemetry: DeviceTelemetry?
  private var refreshTask: Task<Void, Never>?
  private var telemetryTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?

  public init(
    nearby: NearbyServer,
    service: CodexThreadService,
    telemetry: MacTelemetrySampler = MacTelemetrySampler(),
    pairingGate: PairingGate = PairingGate(),
    bridgeName: String = Host.current().localizedName ?? "Mac"
  ) {
    self.nearby = nearby
    self.service = service
    self.telemetry = telemetry
    self.pairingGate = pairingGate
    self.bridgeName = bridgeName
  }

  public var pairingCode: String { pairingGate.code }
  public var pairingExpiration: Date { pairingGate.expiresAt }

  public func start() async {
    nearby.setHandlers(
      envelope: { [weak self] peer, envelope in
        Task { await self?.handle(envelope, from: peer) }
      },
      state: { [weak self] peer, state in
        Task { await self?.peer(peer, changed: state) }
      }
    )
    nearby.start()
    await refreshNow()

    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        await self?.refreshNow()
      }
    }
    telemetryTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.sampleAndBroadcastTelemetry()
        try? await Task.sleep(for: .seconds(2))
      }
    }
    eventTask = Task { [weak self, events = service.events] in
      for await event in events {
        guard !Task.isCancelled else { return }
        await self?.handleAppServerEvent(event)
      }
    }
  }

  public func stop() {
    refreshTask?.cancel()
    telemetryTask?.cancel()
    eventTask?.cancel()
    nearby.stop()
  }

  private func handle(_ envelope: BridgeEnvelope, from peer: String) async {
    switch envelope.message {
    case .clientHello(let hello):
      guard hello.protocolVersion == BridgeEnvelope.currentProtocolVersion else {
        sendError(
          code: "protocol_version",
          message: "Update Eng on both devices before reconnecting.",
          recoverable: false,
          relatedTo: envelope.id,
          to: peer
        )
        return
      }
      peerDevices[peer] = hello.deviceID
    case .pair(let request):
      peerDevices[peer] = request.deviceID
      let result = pairingGate.validate(
        code: request.code,
        deviceID: request.deviceID,
        bridgeName: bridgeName
      )
      try? nearby.send(BridgeEnvelope(message: .pairResult(result)), to: peer)
      if result.accepted {
        pairedPeers.insert(peer)
        await sendInitialState(to: peer)
      }
    default:
      guard pairedPeers.contains(peer) else {
        sendError(
          code: "pairing_required",
          message: "Enter the pairing code shown on the Mac.",
          recoverable: true,
          relatedTo: envelope.id,
          to: peer
        )
        return
      }
      await handlePaired(envelope, from: peer)
    }
  }

  private func handlePaired(_ envelope: BridgeEnvelope, from peer: String) async {
    do {
      switch envelope.message {
      case .refresh:
        await refreshNow()
        if let workspace = lastWorkspace {
          try nearby.send(BridgeEnvelope(message: .workspaceSnapshot(workspace)), to: peer)
        }
      case .subscribe(let subscription):
        subscriptions[peer] = subscription.threadID
        let detail = try await service.subscribe(threadID: subscription.threadID)
        try nearby.send(BridgeEnvelope(message: .threadDetail(detail)), to: peer)
      case .sendMessage(let request):
        _ = try await service.sendMessage(threadID: request.threadID, text: request.normalizedText)
        let detail = try await service.threadDetail(threadID: request.threadID)
        try nearby.send(BridgeEnvelope(message: .threadDetail(detail)), to: peer)
      case .interrupt(let request):
        try await service.interrupt(threadID: request.threadID, turnID: request.turnID)
      case .approvalResponse(let response):
        try await service.answerApproval(response)
        await sendSubscribedDetail(to: peer)
      case .userInputResponse(let response):
        try await service.answerUserInput(response)
        await sendSubscribedDetail(to: peer)
      case .analytics(let snapshot):
        phoneAnalytics[peer] = snapshot
        await sendAnalytics(to: peer)
      case .ping(let ping):
        let receivedAt = Date()
        let pong = Pong(
          sequence: ping.sequence,
          clientSentAt: ping.clientSentAt,
          bridgeReceivedAt: receivedAt,
          payloadBytes: ping.payloadBytes
        )
        try nearby.send(BridgeEnvelope(message: .pong(pong)), to: peer)
      case .clientHello, .pair, .pairResult, .workspaceSnapshot, .threadDetail,
        .timelineEvent, .pong, .error:
        break
      }
    } catch {
      sendError(
        code: "bridge_operation",
        message: error.localizedDescription,
        recoverable: true,
        relatedTo: envelope.id,
        to: peer
      )
    }
  }

  private func refreshNow() async {
    do {
      let workspace = try await service.refreshWorkspace()
      lastWorkspace = workspace
      for peer in pairedPeers {
        try? nearby.send(BridgeEnvelope(message: .workspaceSnapshot(workspace)), to: peer)
      }
    } catch {
      for peer in pairedPeers {
        sendError(
          code: "workspace_refresh",
          message: error.localizedDescription,
          recoverable: true,
          relatedTo: nil,
          to: peer
        )
      }
    }
  }

  private func sampleAndBroadcastTelemetry() async {
    lastMacTelemetry = await telemetry.sample()
    for peer in pairedPeers {
      await sendAnalytics(to: peer)
    }
  }

  private func sendInitialState(to peer: String) async {
    if lastWorkspace == nil { await refreshNow() }
    if let workspace = lastWorkspace {
      try? nearby.send(BridgeEnvelope(message: .workspaceSnapshot(workspace)), to: peer)
    }
    await sendAnalytics(to: peer)
  }

  private func sendAnalytics(to peer: String) async {
    if lastMacTelemetry == nil { lastMacTelemetry = await telemetry.sample() }
    let phone = phoneAnalytics[peer]?.phone
    let link = phoneAnalytics[peer]?.link ?? LinkTelemetry()
    let snapshot = AnalyticsSnapshot(phone: phone, mac: lastMacTelemetry, link: link)
    try? nearby.send(BridgeEnvelope(message: .analytics(snapshot)), to: peer)
  }

  private func handleAppServerEvent(_ event: AppServerInbound) async {
    switch event {
    case .request(let id, let method, let params):
      guard let action = await service.recordServerRequest(id: id, method: method, params: params)
      else { return }
      for (peer, threadID) in subscriptions where threadID == action.threadID {
        await sendSubscribedDetail(to: peer)
      }
    case .notification(let method, let params):
      if let item = CodexTimelineMapper.mapEvent(method: method, params: params) {
        for (peer, threadID) in subscriptions where threadID == item.threadID {
          try? nearby.send(BridgeEnvelope(message: .timelineEvent(item)), to: peer)
        }
      }
      if method == "turn/completed" || method == "thread/status/changed" {
        await refreshNow()
        if let threadID = params["threadId"]?.stringValue {
          for (peer, selectedID) in subscriptions where selectedID == threadID {
            await sendSubscribedDetail(to: peer)
          }
        }
      }
    }
  }

  private func sendSubscribedDetail(to peer: String) async {
    guard let threadID = subscriptions[peer],
      let detail = try? await service.threadDetail(threadID: threadID)
    else { return }
    try? nearby.send(BridgeEnvelope(message: .threadDetail(detail)), to: peer)
  }

  private func peer(_ peer: String, changed state: MCSessionState) {
    if state != .connected {
      pairedPeers.remove(peer)
      subscriptions.removeValue(forKey: peer)
      phoneAnalytics.removeValue(forKey: peer)
    }
  }

  private func sendError(
    code: String,
    message: String,
    recoverable: Bool,
    relatedTo id: UUID?,
    to peer: String
  ) {
    let error = BridgeError(
      code: code,
      message: message,
      recoverable: recoverable,
      relatedMessageID: id
    )
    try? nearby.send(BridgeEnvelope(message: .error(error)), to: peer)
  }
}
