import Foundation
import UIKit

struct AnalyticsPoint: Identifiable, Equatable, Sendable {
  let id: Date
  let sampledAt: Date
  let cpuPercent: Double?
  let memoryFraction: Double?
  let downloadBytesPerSecond: Double?
  let uploadBytesPerSecond: Double?

  init(_ telemetry: DeviceTelemetry) {
    id = telemetry.sampledAt
    sampledAt = telemetry.sampledAt
    cpuPercent = telemetry.cpuUsagePercent
    if let used = telemetry.memoryUsedBytes,
      let total = telemetry.memoryTotalBytes,
      total > 0
    {
      memoryFraction = Double(used) / Double(total)
    } else {
      memoryFraction = nil
    }
    downloadBytesPerSecond = telemetry.downloadBytesPerSecond
    uploadBytesPerSecond = telemetry.uploadBytesPerSecond
  }
}

@MainActor
final class BridgeStore: ObservableObject {
  @Published private(set) var connection: NearbyConnectionState = .searching
  @Published private(set) var isPaired = false
  @Published private(set) var bridgeName: String?
  @Published private(set) var workspace: WorkspaceSnapshot?
  @Published private(set) var threadDetail: ThreadDetail?
  @Published private(set) var analytics = AnalyticsSnapshot(
    phone: nil,
    mac: nil,
    link: LinkTelemetry()
  )
  @Published private(set) var phoneHistory: [AnalyticsPoint] = []
  @Published private(set) var macHistory: [AnalyticsPoint] = []
  @Published private(set) var isSending = false
  @Published var pairingCode = ""
  @Published var presentedError: BridgeError?

  private let deviceID: UUID
  private let client: NearbyClient
  private let telemetrySampler = PhoneTelemetrySampler()
  private let demoMode: Bool
  private var telemetryTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var started = false
  private var pingSequence: UInt64 = 0
  private var pendingPings: [UInt64: Date] = [:]
  private var latestPhoneSample: PhoneTelemetrySample?

  init() {
    demoMode = ProcessInfo.processInfo.arguments.contains("-eng-demo")
    deviceID = Self.loadDeviceID()
    client = NearbyClient(displayName: UIDevice.current.name)
    client.setEventHandler { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
    if demoMode { applyDemoState() }
  }

  deinit {
    telemetryTask?.cancel()
    refreshTask?.cancel()
  }

  var projects: [ProjectSummary] { workspace?.projects ?? [] }

  var isConnected: Bool {
    if case .connected = connection { return true }
    return false
  }

  var connectionLabel: String {
    switch connection {
    case .searching: "Looking for Mac"
    case .connecting(let name): "Connecting to \(name)"
    case .connected: isPaired ? "Live" : "Pair Mac"
    case .disconnected: "Reconnecting"
    case .failed: "Connection issue"
    }
  }

  func start() {
    guard !started else { return }
    started = true
    if demoMode { return }
    client.start()

    telemetryTask = Task { [weak self] in
      while !Task.isCancelled {
        self?.samplePhone()
        try? await Task.sleep(for: .seconds(2))
      }
    }

    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        if self?.isPaired == true {
          self?.refresh()
          self?.sendPing()
        }
        try? await Task.sleep(for: .seconds(5))
      }
    }
  }

  func pair() {
    let code = pairingCode.filter(\.isNumber)
    guard code.count == 6 else {
      presentedError = BridgeError(
        code: "pairing_code",
        message: "Enter the six-digit code shown by Eng Bridge on your Mac.",
        recoverable: true
      )
      return
    }
    send(
      .pair(
        PairRequest(code: code, deviceID: deviceID, deviceName: UIDevice.current.name)))
  }

  func refresh(threadID: String? = nil) {
    guard isPaired else { return }
    send(.refresh(RefreshRequest(threadID: threadID)))
  }

  func subscribe(to thread: ThreadSummary) {
    if demoMode {
      #if DEBUG
        threadDetail = DemoFixtures.threadDetail
      #endif
      return
    }
    threadDetail = nil
    send(.subscribe(ThreadSubscription(threadID: thread.id)))
  }

  func sendMessage(_ text: String, to threadID: String) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    isSending = true
    send(.sendMessage(SendMessageRequest(threadID: threadID, text: normalized)))
  }

  func interrupt(threadID: String, turnID: String) {
    send(.interrupt(InterruptRequest(threadID: threadID, turnID: turnID)))
  }

  func answerApproval(requestID: String, decision: ApprovalDecision) {
    send(.approvalResponse(ApprovalResponse(requestID: requestID, decision: decision)))
  }

  func answerUserInput(requestID: String, optionID: String) {
    let components = optionID.split(separator: "::", maxSplits: 1).map(String.init)
    let questionID = components.first ?? "answer"
    let answer = components.count > 1 ? components[1] : optionID
    send(.userInputResponse(UserInputResponse(requestID: requestID, answers: [questionID: answer])))
  }

  func dismissError() {
    presentedError = nil
  }

  private func handle(_ event: NearbyClientEvent) {
    switch event {
    case .state(let state):
      connection = state
      if case .connected = state {
        sendHello()
        attemptTrustedReconnect()
      } else if case .disconnected = state {
        isPaired = false
      } else if case .failed(let message) = state {
        isPaired = false
        presentedError = BridgeError(
          code: "nearby_connection",
          message: message,
          recoverable: true
        )
      }
    case .envelope(let envelope):
      handle(envelope)
    }
  }

  private func handle(_ envelope: BridgeEnvelope) {
    switch envelope.message {
    case .pairResult(let result):
      bridgeName = result.bridgeName
      isPaired = result.accepted
      if result.accepted {
        pairingCode = ""
        presentedError = nil
        refresh()
        sendPing()
      } else if let reason = result.reason {
        presentedError = BridgeError(
          code: "pairing_required",
          message: reason,
          recoverable: true,
          relatedMessageID: envelope.id
        )
      }
    case .workspaceSnapshot(let snapshot):
      workspace = snapshot
    case .threadDetail(let detail):
      threadDetail = detail
      isSending = false
    case .timelineEvent(let item):
      mergeTimelineEvent(item)
    case .analytics(let snapshot):
      let phone = latestPhoneSample?.telemetry ?? snapshot.phone
      analytics = AnalyticsSnapshot(phone: phone, mac: snapshot.mac, link: analytics.link)
      if let mac = snapshot.mac { appendHistory(mac, to: &macHistory) }
    case .pong(let pong):
      receive(pong)
    case .error(let error):
      isSending = false
      if error.code == "pairing_required" { isPaired = false }
      presentedError = error
    case .clientHello, .pair, .refresh, .subscribe, .sendMessage, .interrupt,
      .approvalResponse, .userInputResponse, .ping:
      break
    }
  }

  private func mergeTimelineEvent(_ item: TimelineItem) {
    guard var detail = threadDetail, detail.thread.id == item.threadID else { return }
    var timeline = detail.timeline

    if let index = timeline.firstIndex(where: { $0.id == item.id }) {
      timeline[index] = item
    } else if item.state == .running,
      let last = timeline.last,
      last.state == .running,
      last.kind == item.kind,
      last.turnID == item.turnID
    {
      timeline[timeline.count - 1] = TimelineItem(
        id: last.id,
        threadID: last.threadID,
        turnID: last.turnID,
        kind: last.kind,
        state: .running,
        title: last.title,
        body: last.body + item.body,
        timestamp: last.timestamp
      )
    } else {
      timeline.append(item)
    }

    detail = ThreadDetail(
      thread: detail.thread,
      timeline: timeline,
      pendingActions: detail.pendingActions,
      refreshedAt: Date()
    )
    threadDetail = detail
  }

  private func samplePhone() {
    let sample = telemetrySampler.sample()
    latestPhoneSample = sample
    appendHistory(sample.telemetry, to: &phoneHistory)

    let link = LinkTelemetry(
      sampledAt: analytics.link.sampledAt,
      roundTripMilliseconds: analytics.link.roundTripMilliseconds,
      measuredBytesPerSecond: analytics.link.measuredBytesPerSecond,
      quality: analytics.link.quality,
      isExpensive: sample.isExpensive,
      isConstrained: sample.isConstrained
    )
    analytics = AnalyticsSnapshot(phone: sample.telemetry, mac: analytics.mac, link: link)

    guard isPaired else { return }
    send(.analytics(AnalyticsSnapshot(phone: sample.telemetry, mac: nil, link: link)))
  }

  private func sendPing() {
    guard isPaired else { return }
    pingSequence &+= 1
    let now = Date()
    pendingPings[pingSequence] = now
    pendingPings = pendingPings.filter { now.timeIntervalSince($0.value) < 30 }
    send(.ping(Ping(sequence: pingSequence, clientSentAt: now, payloadBytes: 65_536)))
  }

  private func receive(_ pong: Pong) {
    let receivedAt = Date()
    guard let sentAt = pendingPings.removeValue(forKey: pong.sequence) else { return }
    let duration = max(receivedAt.timeIntervalSince(sentAt), 0.001)
    let latency = duration * 1_000
    let payloadRate = Double(pong.payloadBytes * 2) / duration
    let constrained = latestPhoneSample?.isConstrained ?? false
    let link = LinkTelemetry(
      sampledAt: receivedAt,
      roundTripMilliseconds: latency,
      measuredBytesPerSecond: payloadRate,
      quality: TelemetryAnalysis.connectionQuality(
        roundTripMilliseconds: latency,
        measuredBytesPerSecond: payloadRate,
        constrained: constrained
      ),
      isExpensive: latestPhoneSample?.isExpensive,
      isConstrained: constrained
    )
    analytics = AnalyticsSnapshot(phone: analytics.phone, mac: analytics.mac, link: link)
  }

  private func appendHistory(_ telemetry: DeviceTelemetry, to values: inout [AnalyticsPoint]) {
    guard values.last?.sampledAt != telemetry.sampledAt else { return }
    values.append(AnalyticsPoint(telemetry))
    if values.count > 90 { values.removeFirst(values.count - 90) }
  }

  private func sendHello() {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "0.1.0"
    send(
      .clientHello(
        ClientHello(
          deviceID: deviceID,
          deviceName: UIDevice.current.name,
          appVersion: version
        )))
  }

  private func attemptTrustedReconnect() {
    send(
      .pair(
        PairRequest(code: "", deviceID: deviceID, deviceName: UIDevice.current.name)))
  }

  private func send(_ message: BridgeMessage) {
    do {
      try client.send(BridgeEnvelope(message: message))
    } catch let error as BridgeError {
      presentedError = error
    } catch {
      presentedError = BridgeError(
        code: "phone_send",
        message: error.localizedDescription,
        recoverable: true
      )
    }
  }

  private static func loadDeviceID() -> UUID {
    let key = "eng.device-id"
    if let value = UserDefaults.standard.string(forKey: key),
      let id = UUID(uuidString: value)
    {
      return id
    }
    let id = UUID()
    UserDefaults.standard.set(id.uuidString, forKey: key)
    return id
  }

  private func applyDemoState() {
    #if DEBUG
      connection = .connected("Jordan’s MacBook Pro")
      isPaired = true
      bridgeName = "Jordan’s MacBook Pro"
      workspace = DemoFixtures.workspace
      threadDetail = DemoFixtures.threadDetail
      analytics = DemoFixtures.analytics
      phoneHistory = DemoFixtures.phoneHistory
      macHistory = DemoFixtures.macHistory
    #endif
  }
}
