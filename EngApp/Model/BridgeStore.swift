import EngCore
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
  @Published private(set) var connection: BridgeConnectionState = .searching
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
  @Published private(set) var activitySummaries: [String: String] = [:]
  @Published private(set) var pinnedProjectIDs: Set<String>
  @Published var focusPinnedOnly: Bool {
    didSet { preferences.set(focusPinnedOnly, forKey: PreferenceKey.focusPinnedOnly) }
  }
  @Published var connectionPreference: ConnectionPreference {
    didSet {
      preferences.set(connectionPreference.rawValue, forKey: PreferenceKey.connectionPreference)
      client.setConnectionPreference(connectionPreference)
    }
  }
  @Published var pairingCode = ""
  @Published var presentedError: BridgeError?

  private let deviceID: UUID
  private let client: any BridgeClientTransport
  private let preferences: UserDefaults
  private let telemetrySampler = PhoneTelemetrySampler()
  private let demoMode: Bool
  private let automaticPairingCode: String?
  private var telemetryTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var started = false
  private var pingSequence: UInt64 = 0
  private var pendingPings: [UInt64: Date] = [:]
  private var latestPhoneSample: PhoneTelemetrySample?
  private var secureTransportBootstrap: TransportBootstrap?
  private var selectedThreadID: String?
  private var pendingWorkspaceID: UUID?
  /// True while an automatic empty-code pair probe is outstanding; a rejection of that
  /// probe is expected on first pairing and must not surface as an error.
  private var awaitingTrustedReconnect = false
  private var pendingWorkspacePages: [Int: WorkspacePage] = [:]
  private var optimisticMessages: [String: [TimelineItem]] = [:]

  convenience init() {
    self.init(client: nil, arguments: ProcessInfo.processInfo.arguments)
  }

  /// `client` defaults to the adaptive direct-local/Nearby transport. Tests inject a fake
  /// so store logic (paging, timeline merging, link probes) runs without radios.
  init(
    client: (any BridgeClientTransport)?, arguments: [String],
    preferences: UserDefaults = .standard
  ) {
    self.preferences = preferences
    pinnedProjectIDs = Set(preferences.stringArray(forKey: PreferenceKey.pinnedProjectIDs) ?? [])
    focusPinnedOnly = preferences.bool(forKey: PreferenceKey.focusPinnedOnly)
    connectionPreference =
      preferences.string(forKey: PreferenceKey.connectionPreference)
      .flatMap(ConnectionPreference.init(rawValue:)) ?? .automatic
    demoMode = arguments.contains("-eng-demo")
    if let index = arguments.firstIndex(of: "-eng-pair-code"),
      arguments.indices.contains(index + 1)
    {
      automaticPairingCode = arguments[index + 1]
    } else {
      automaticPairingCode = nil
    }
    deviceID = Self.loadDeviceID(from: preferences)
    self.client =
      client
      ?? AdaptiveBridgeClient(displayName: UIDevice.current.name, deviceID: deviceID)
    self.client.setEventHandler { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
    self.client.setConnectionPreference(connectionPreference)
    if demoMode { applyDemoState() }
  }

  deinit {
    telemetryTask?.cancel()
    refreshTask?.cancel()
  }

  var projects: [ProjectSummary] { workspace?.projects ?? [] }

  var pinnedProjectCount: Int {
    projects.lazy.filter { self.pinnedProjectIDs.contains($0.id) }.count
  }

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

  var activePathLabel: String {
    guard case .connected(let endpoint) = connection else { return client.kind.title }
    let parts = endpoint.split(separator: "·", maxSplits: 1)
    return parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : endpoint
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
        PairRequest(
          code: code,
          deviceID: deviceID,
          deviceName: UIDevice.current.name,
          identityPublicKey: client.identityPublicKey
        )))
  }

  func refresh(threadID: String? = nil) {
    guard isPaired else { return }
    send(.refresh(RefreshRequest(threadID: threadID)))
  }

  func isProjectPinned(_ projectID: String) -> Bool {
    pinnedProjectIDs.contains(projectID)
  }

  func currentActivitySummary(for thread: ThreadSummary) -> String? {
    guard thread.status == .active || thread.status == .waiting else { return nil }
    return activitySummaries[thread.id]
  }

  func toggleProjectPin(_ projectID: String) {
    if pinnedProjectIDs.contains(projectID) {
      pinnedProjectIDs.remove(projectID)
    } else {
      pinnedProjectIDs.insert(projectID)
    }
    preferences.set(Array(pinnedProjectIDs).sorted(), forKey: PreferenceKey.pinnedProjectIDs)
  }

  func subscribe(to thread: ThreadSummary) {
    if demoMode {
      #if DEBUG
        threadDetail = DemoFixtures.threadDetail
      #endif
      return
    }
    threadDetail = nil
    selectedThreadID = thread.id
    send(.subscribe(ThreadSubscription(threadID: thread.id)))
  }

  func sendMessage(_ text: String, to threadID: String) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    let optimistic = TimelineItem(
      id: "local:user:\(UUID().uuidString)",
      threadID: threadID,
      turnID: threadDetail?.thread.id == threadID ? threadDetail?.thread.activeTurnID : nil,
      kind: .user,
      state: .pending,
      title: "You",
      body: normalized,
      timestamp: Date()
    )
    optimisticMessages[threadID, default: []].append(optimistic)
    appendOptimistic(optimistic)
    activitySummaries[threadID] = "Thinking"
    isSending = true
    if !send(.sendMessage(SendMessageRequest(threadID: threadID, text: normalized))) {
      markLatestOptimisticMessageFailed(threadID: threadID)
      isSending = false
    }
  }

  func interrupt(threadID: String, turnID: String) {
    send(.interrupt(InterruptRequest(threadID: threadID, turnID: turnID)))
  }

  func answerApproval(requestID: String, decision: ApprovalDecision) {
    send(.approvalResponse(ApprovalResponse(requestID: requestID, decision: decision)))
  }

  func answerUserInput(requestID: String, answers: [String: String]) {
    let normalized = answers.mapValues {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !normalized.isEmpty, normalized.values.allSatisfy({ !$0.isEmpty }) else { return }
    send(.userInputResponse(UserInputResponse(requestID: requestID, answers: normalized)))
  }

  func dismissError() {
    presentedError = nil
  }

  func handleForTesting(_ event: BridgeClientEvent) {
    handle(event)
  }

  private func handle(_ event: BridgeClientEvent) {
    switch event {
    case .state(let state):
      connection = state
      if case .connected = state {
        sendHello()
        #if DEBUG
          if let automaticPairingCode {
            pairingCode = automaticPairingCode
            pair()
          } else {
            attemptTrustedReconnect()
          }
        #else
          attemptTrustedReconnect()
        #endif
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
      receive(envelope)
    }
  }

  func receive(_ envelope: BridgeEnvelope) {
    switch envelope.message {
    case .pairResult(let result):
      bridgeName = result.bridgeName
      isPaired = result.accepted
      let wasSilentProbe = awaitingTrustedReconnect
      awaitingTrustedReconnect = false
      if result.accepted {
        pairingCode = ""
        presentedError = nil
        refresh()
        sendPing()
        if let selectedThreadID {
          send(.subscribe(ThreadSubscription(threadID: selectedThreadID)))
        }
      } else if wasSilentProbe {
        // Expected on first connect: the device is not yet trusted by this bridge.
        break
      } else if let reason = result.reason {
        presentedError = BridgeError(
          code: "pairing_required",
          message: reason,
          recoverable: true,
          relatedMessageID: envelope.id
        )
      }
    case .transportBootstrap(let bootstrap):
      guard bootstrap.deviceID == deviceID, bootstrap.isValid() else { return }
      secureTransportBootstrap = bootstrap
      client.install(bootstrap)
    case .workspaceSnapshot(let snapshot):
      workspace = snapshot
      pendingWorkspaceID = nil
      pendingWorkspacePages = [:]
    case .workspacePage(let page):
      receive(page)
    case .threadDetail(let detail):
      let reconciled = reconcileOptimisticMessages(in: detail)
      threadDetail = reconciled
      rememberActivity(in: reconciled)
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
      if let selectedThreadID { markLatestOptimisticMessageFailed(threadID: selectedThreadID) }
      isSending = false
      if error.code == "pairing_required" { isPaired = false }
      presentedError = error
    case .clientHello, .pair, .refresh, .subscribe, .sendMessage, .interrupt,
      .approvalResponse, .userInputResponse, .ping:
      break
    }
  }

  private func receive(_ page: WorkspacePage) {
    if pendingWorkspaceID != page.snapshotID {
      pendingWorkspaceID = page.snapshotID
      pendingWorkspacePages = [:]
    }
    pendingWorkspacePages[page.pageIndex] = page
    guard
      let snapshot = WorkspacePager.assemble(Array(pendingWorkspacePages.values))
    else { return }
    workspace = snapshot
    pendingWorkspaceID = nil
    pendingWorkspacePages = [:]
  }

  private func mergeTimelineEvent(_ item: TimelineItem) {
    guard var detail = threadDetail, detail.thread.id == item.threadID else { return }
    var timeline = detail.timeline

    if item.kind == .user,
      let optimisticIndex = timeline.firstIndex(where: {
        $0.id.hasPrefix("local:user:") && messagesMatch($0, item)
      })
    {
      let optimisticID = timeline[optimisticIndex].id
      timeline.remove(at: optimisticIndex)
      optimisticMessages[item.threadID]?.removeAll { $0.id == optimisticID }
    }

    if item.state != .running,
      let index = timeline.lastIndex(where: {
        $0.state == .running && $0.kind == item.kind && $0.turnID == item.turnID
      })
    {
      timeline[index] = item
    } else if let index = timeline.firstIndex(where: { $0.id == item.id }) {
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
    rememberActivity(in: detail)
  }

  private func rememberActivity(in detail: ThreadDetail) {
    guard
      let activity = ThreadActivityPresentation.current(
        thread: detail.thread,
        timeline: detail.timeline,
        pendingActions: detail.pendingActions,
        isSending: isSending
      )
    else {
      activitySummaries.removeValue(forKey: detail.thread.id)
      return
    }
    activitySummaries[detail.thread.id] =
      [activity.title, activity.detail].compactMap { $0 }.joined(separator: ": ")
  }

  private func appendOptimistic(_ item: TimelineItem) {
    guard let detail = threadDetail, detail.thread.id == item.threadID else { return }
    threadDetail = ThreadDetail(
      thread: detail.thread,
      timeline: detail.timeline + [item],
      pendingActions: detail.pendingActions,
      refreshedAt: Date()
    )
  }

  private func reconcileOptimisticMessages(in detail: ThreadDetail) -> ThreadDetail {
    guard var pending = optimisticMessages[detail.thread.id], !pending.isEmpty else {
      return detail
    }
    var unmatchedServerUsers = detail.timeline.filter { $0.kind == .user }
    pending.removeAll { optimistic in
      guard
        let match = unmatchedServerUsers.firstIndex(where: {
          messagesMatch(optimistic, $0)
            && $0.timestamp >= optimistic.timestamp.addingTimeInterval(-30)
        })
      else { return false }
      unmatchedServerUsers.remove(at: match)
      return true
    }

    let acknowledged = pending.map { item in
      TimelineItem(
        id: item.id,
        threadID: item.threadID,
        turnID: item.turnID,
        kind: item.kind,
        state: item.state == .failed ? .failed : .completed,
        title: item.title,
        body: item.body,
        timestamp: item.timestamp
      )
    }
    optimisticMessages[detail.thread.id] = acknowledged
    return ThreadDetail(
      thread: detail.thread,
      timeline: detail.timeline + acknowledged,
      pendingActions: detail.pendingActions,
      refreshedAt: detail.refreshedAt
    )
  }

  private func markLatestOptimisticMessageFailed(threadID: String) {
    guard var items = optimisticMessages[threadID], let last = items.indices.last else { return }
    let failed = TimelineItem(
      id: items[last].id,
      threadID: items[last].threadID,
      turnID: items[last].turnID,
      kind: items[last].kind,
      state: .failed,
      title: items[last].title,
      body: items[last].body,
      timestamp: items[last].timestamp
    )
    items[last] = failed
    optimisticMessages[threadID] = items
    guard let detail = threadDetail, detail.thread.id == threadID,
      let index = detail.timeline.firstIndex(where: { $0.id == failed.id })
    else { return }
    var timeline = detail.timeline
    timeline[index] = failed
    threadDetail = ThreadDetail(
      thread: detail.thread,
      timeline: timeline,
      pendingActions: detail.pendingActions,
      refreshedAt: Date()
    )
  }

  private func messagesMatch(_ lhs: TimelineItem, _ rhs: TimelineItem) -> Bool {
    lhs.body.trimmingCharacters(in: .whitespacesAndNewlines)
      == rhs.body.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func samplePhone() {
    let sample = telemetrySampler.sample()
    latestPhoneSample = sample
    appendHistory(sample.telemetry, to: &phoneHistory)

    let link = LinkTelemetry(
      sampledAt: analytics.link.sampledAt,
      transport: client.kind,
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

  func sendPing() {
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
      transport: client.kind,
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
    awaitingTrustedReconnect = true
    let identityByteCount = client.identityPublicKey?.count ?? 0
    FileHandle.standardError.write(
      Data("[Eng Pairing] Sending \(identityByteCount)-byte device identity\n".utf8)
    )
    send(
      .pair(
        PairRequest(
          code: "",
          deviceID: deviceID,
          deviceName: UIDevice.current.name,
          identityPublicKey: client.identityPublicKey
        )))
  }

  @discardableResult
  private func send(_ message: BridgeMessage) -> Bool {
    do {
      try client.send(BridgeEnvelope(message: message))
      return true
    } catch let error as BridgeError {
      presentedError = error
      return false
    } catch {
      presentedError = BridgeError(
        code: "phone_send",
        message: error.localizedDescription,
        recoverable: true
      )
      return false
    }
  }

  private static func loadDeviceID(from preferences: UserDefaults) -> UUID {
    let key = "eng.device-id"
    if let value = preferences.string(forKey: key),
      let id = UUID(uuidString: value)
    {
      return id
    }
    let id = UUID()
    preferences.set(id.uuidString, forKey: key)
    return id
  }

  private enum PreferenceKey {
    static let pinnedProjectIDs = "eng.pinned-project-ids"
    static let focusPinnedOnly = "eng.focus-pinned-only"
    static let connectionPreference = "eng.connection-preference"
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
