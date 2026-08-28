import EngCore
import Foundation

public actor BridgeCoordinator {
  private let transport: any BridgeServerTransport
  private let service: CodexThreadService
  private let telemetry: MacTelemetrySampler
  private let bridgeName: String
  private let statusHandler: @Sendable (String) -> Void
  private let trustedDeviceHandler: @Sendable (UUID, Data?) throws -> Void
  private let trustedIdentityValidator: @Sendable (UUID, Data) -> Bool
  private let transportRegistry: SecureTransportRegistry
  private var pairingGate: PairingGate
  private var pairedPeers = Set<String>()
  private var peerDevices: [String: UUID] = [:]
  private var subscriptions: [String: String] = [:]
  private var phoneAnalytics: [String: AnalyticsSnapshot] = [:]
  private var reportedPhoneTelemetryPeers = Set<String>()
  private var reportedLinkTelemetryPeers = Set<String>()
  private var reportedWorkspaceShape: String?
  private var lastWorkspace: WorkspaceSnapshot?
  private var lastMacTelemetry: DeviceTelemetry?
  private var lastSentDetails: [String: ThreadDetail] = [:]
  private var refreshTask: Task<Void, Never>?
  private var telemetryTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?

  public init(
    transport: any BridgeServerTransport,
    service: CodexThreadService,
    telemetry: MacTelemetrySampler = MacTelemetrySampler(),
    pairingGate: PairingGate = PairingGate(),
    transportRegistry: SecureTransportRegistry = SecureTransportRegistry(),
    bridgeName: String = Host.current().localizedName ?? "Mac",
    trustedDeviceHandler: @escaping @Sendable (UUID, Data?) throws -> Void = { _, _ in },
    trustedIdentityValidator: @escaping @Sendable (UUID, Data) -> Bool = { _, _ in true },
    statusHandler: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.transport = transport
    self.service = service
    self.telemetry = telemetry
    self.pairingGate = pairingGate
    self.transportRegistry = transportRegistry
    self.bridgeName = bridgeName
    self.trustedDeviceHandler = trustedDeviceHandler
    self.trustedIdentityValidator = trustedIdentityValidator
    self.statusHandler = statusHandler
  }

  public var pairingCode: String { pairingGate.code }
  public var pairingExpiration: Date { pairingGate.expiresAt }

  public func start() async {
    transport.setHandlers(
      envelope: { [weak self] peer, envelope in
        Task { await self?.handle(envelope, from: peer) }
      },
      state: { [weak self] peer, state in
        Task { await self?.peer(peer, changed: state) }
      }
    )
    transport.start()
    await refreshNow()

    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        await self?.refreshNow()
        await self?.pollSubscribedDetails()
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
    transport.stop()
  }

  public func appServerRecovered() async {
    do {
      try await service.recoverSubscriptions()
    } catch {
      statusHandler("Could not restore live thread subscriptions: \(error.localizedDescription)")
    }
    await refreshNow(forceBroadcast: true)
    for peer in subscriptions.keys {
      await sendSubscribedDetail(to: peer)
    }
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
      let wasTrusted = pairingGate.isPaired(deviceID: request.deviceID)
      statusHandler(
        "Pair request from \(request.deviceName) included "
          + "\(request.identityPublicKey?.count ?? 0) identity bytes."
      )
      let identityMatches =
        request.identityPublicKey.map {
          trustedIdentityValidator(request.deviceID, $0)
        } ?? !wasTrusted
      let result =
        identityMatches
        ? pairingGate.validate(
          code: request.code,
          deviceID: request.deviceID,
          bridgeName: bridgeName
        )
        : PairResult(
          accepted: false,
          bridgeName: bridgeName,
          reason: "This iPhone identity does not match the remembered device."
        )
      try? transport.send(BridgeEnvelope(message: .pairResult(result)), to: peer)
      if result.accepted {
        do {
          try trustedDeviceHandler(request.deviceID, request.identityPublicKey)
          if !wasTrusted {
            statusHandler("Remembered this iPhone for automatic reconnection.")
          }
        } catch {
          statusHandler(
            "Paired, but could not remember this iPhone: \(error.localizedDescription)")
        }
        pairedPeers.insert(peer)
        let peerTransport = transport.kind(for: peer)
        statusHandler(
          "Paired \(request.deviceName) over \(peerTransport.title) "
            + "(\(peerTransport.securityLabel))."
        )
        if let credential = try? transportCredential(for: request.deviceID) {
          try? transport.send(
            BridgeEnvelope(message: .transportBootstrap(credential)),
            to: peer
          )
        }
        await sendInitialState(to: peer)
      } else {
        statusHandler("Pairing rejected for \(request.deviceName): \(result.reason ?? "unknown")")
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
    guard PhoneCommandPolicy.permits(envelope.message) else {
      sendError(
        code: "phone_command_denied",
        message: "This operation is outside the phone control policy.",
        recoverable: false,
        relatedTo: envelope.id,
        to: peer
      )
      return
    }
    do {
      switch envelope.message {
      case .refresh:
        await refreshNow(forceBroadcast: true)
      case .subscribe(let subscription):
        subscriptions[peer] = subscription.threadID
        let detail = try await service.subscribe(threadID: subscription.threadID)
        try send(detail, to: peer)
      case .sendMessage(let request):
        _ = try await service.sendMessage(threadID: request.threadID, text: request.normalizedText)
        let detail = try await service.threadDetail(threadID: request.threadID)
        try transport.send(BridgeEnvelope(message: .threadDetail(detail)), to: peer)
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
        if let phone = snapshot.phone, reportedPhoneTelemetryPeers.insert(peer).inserted {
          let cpu = phone.cpuUsagePercent.map { String(format: "%.1f%%", $0) } ?? "unavailable"
          statusHandler(
            "Phone diagnostics received from \(phone.name): CPU \(cpu), thermal \(phone.thermalLevel.rawValue), interface \(phone.interface.rawValue)."
          )
        }
        if let latency = snapshot.link.roundTripMilliseconds,
          let speed = snapshot.link.measuredBytesPerSecond,
          reportedLinkTelemetryPeers.insert(peer).inserted
        {
          statusHandler(
            String(
              format: "Bridge link measured at %.1f ms round trip and %.2f MB/s payload goodput.",
              latency,
              speed / 1_000_000
            ))
        }
        await sendAnalytics(to: peer)
      case .ping(let ping):
        let receivedAt = Date()
        let pong = Pong(
          sequence: ping.sequence,
          clientSentAt: ping.clientSentAt,
          bridgeReceivedAt: receivedAt,
          payloadBytes: ping.payloadBytes
        )
        try transport.send(BridgeEnvelope(message: .pong(pong)), to: peer)
      case .clientHello, .pair, .pairResult, .transportBootstrap, .workspaceSnapshot,
        .workspacePage, .threadDetail, .timelineEvent, .pong, .error:
        break
      }
    } catch {
      let message = error.localizedDescription
      statusHandler("Bridge operation failed for \(peer): \(message)")
      sendError(
        code: "bridge_operation",
        message: message,
        recoverable: true,
        relatedTo: envelope.id,
        to: peer
      )
    }
  }

  private func transportCredential(for deviceID: UUID) throws -> TransportBootstrap {
    try transportRegistry.issue(for: deviceID)
  }

  private func refreshNow(forceBroadcast: Bool = false) async {
    do {
      let workspace = try await service.refreshWorkspace()
      let changed = lastWorkspace?.projects != workspace.projects
      lastWorkspace = workspace
      if changed || forceBroadcast {
        if changed {
          let projectCount = workspace.projects.count
          let threadCount = workspace.projects.reduce(0) { $0 + $1.threads.count }
          let pageCount = WorkspacePager.pages(for: workspace).count
          let shape = "\(projectCount):\(threadCount):\(pageCount)"
          if reportedWorkspaceShape != shape {
            reportedWorkspaceShape = shape
            statusHandler(
              "Workspace refreshed: \(projectCount) projects and \(threadCount) threads across \(pageCount) safe frames."
            )
          }
        }
        for peer in pairedPeers {
          try? sendWorkspace(workspace, to: peer)
        }
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
    if lastWorkspace == nil {
      await refreshNow(forceBroadcast: true)
    } else if let workspace = lastWorkspace {
      try? sendWorkspace(workspace, to: peer)
    }
    await sendAnalytics(to: peer)
  }

  private func sendWorkspace(_ workspace: WorkspaceSnapshot, to peer: String) throws {
    for page in WorkspacePager.pages(for: workspace) {
      try transport.send(BridgeEnvelope(message: .workspacePage(page)), to: peer)
    }
  }

  private func sendAnalytics(to peer: String) async {
    if lastMacTelemetry == nil { lastMacTelemetry = await telemetry.sample() }
    let phone = phoneAnalytics[peer]?.phone
    let link = phoneAnalytics[peer]?.link ?? LinkTelemetry()
    let snapshot = AnalyticsSnapshot(phone: phone, mac: lastMacTelemetry, link: link)
    try? transport.send(BridgeEnvelope(message: .analytics(snapshot)), to: peer)
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
      await service.recordNotification(method: method, params: params)
      if let item = CodexTimelineMapper.mapEvent(method: method, params: params) {
        let projected = PhoneTimelineWindow.project([item], maximumItems: 1).first
        for (peer, threadID) in subscriptions where threadID == item.threadID {
          guard let projected else { continue }
          try? transport.send(BridgeEnvelope(message: .timelineEvent(projected)), to: peer)
        }
      }
      if method == "turn/started" || method == "turn/completed"
        || method == "thread/status/changed"
      {
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
    try? send(detail, to: peer)
  }

  private func pollSubscribedDetails() async {
    for peer in subscriptions.keys {
      guard let threadID = subscriptions[peer],
        let detail = try? await service.threadDetail(threadID: threadID),
        detailChanged(detail, from: lastSentDetails[peer])
      else { continue }
      try? send(detail, to: peer)
    }
  }

  private func send(_ detail: ThreadDetail, to peer: String) throws {
    try transport.send(BridgeEnvelope(message: .threadDetail(detail)), to: peer)
    lastSentDetails[peer] = detail
  }

  private func detailChanged(_ detail: ThreadDetail, from previous: ThreadDetail?) -> Bool {
    guard let previous else { return true }
    return detail.thread != previous.thread
      || detail.timeline != previous.timeline
      || detail.pendingActions != previous.pendingActions
  }

  private func peer(_ peer: String, changed state: BridgeTransportPeerState) {
    switch state {
    case .connected:
      statusHandler("Nearby peer connected: \(peer). Waiting for pairing confirmation.")
    case .disconnected:
      statusHandler("Nearby peer disconnected: \(peer).")
    case .connecting:
      break
    @unknown default:
      break
    }
    if state != .connected {
      pairedPeers.remove(peer)
      subscriptions.removeValue(forKey: peer)
      lastSentDetails.removeValue(forKey: peer)
      phoneAnalytics.removeValue(forKey: peer)
      reportedPhoneTelemetryPeers.remove(peer)
      reportedLinkTelemetryPeers.remove(peer)
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
    try? transport.send(BridgeEnvelope(message: .error(error)), to: peer)
  }
}
