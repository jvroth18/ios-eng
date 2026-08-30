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

struct ThreadUnreadNotification: Identifiable, Equatable, Sendable {
  let threadID: String
  let title: String
  let detail: String

  var id: String { threadID }
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
  @Published private(set) var isUpdatingModel = false
  @Published private(set) var activitySummaries: [String: String] = [:]
  @Published private(set) var pinnedProjectIDs: Set<String>
  @Published private(set) var unreadThreadIDs: Set<String>
  @Published private(set) var hiddenThreadIDs: Set<String>
  @Published private(set) var unreadNotification: ThreadUnreadNotification?
  @Published private(set) var threadDrafts: [String: String]
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
  @Published var remoteURL = ""
  @Published var remoteChannelID = ""
  @Published var remoteToken = ""
  @Published private(set) var remoteConfigured = false
  @Published var presentedError: BridgeError?

  private let deviceID: UUID
  private let client: any BridgeClientTransport
  private let preferences: UserDefaults
  private let remoteSecrets: any RemoteRelaySecretStoring
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
  private var visibleThreadID: String?
  private var observedThreadUpdates: [String: TimeInterval]
  private var pendingWorkspaceID: UUID?
  /// True while an automatic empty-code pair probe is outstanding; a rejection of that
  /// probe is expected on first pairing and must not surface as an error.
  private var awaitingTrustedReconnect = false
  private var pendingWorkspacePages: [Int: WorkspacePage] = [:]
  private var optimisticMessages: [String: [TimelineItem]] = [:]
  private var pendingModelUpdate: (threadID: String, previousModel: String?)?

  convenience init() {
    self.init(client: nil, arguments: ProcessInfo.processInfo.arguments)
  }

  /// `client` defaults to the adaptive direct-local/Nearby transport. Tests inject a fake
  /// so store logic (paging, timeline merging, link probes) runs without radios.
  init(
    client: (any BridgeClientTransport)?, arguments: [String],
    preferences: UserDefaults = .standard,
    remoteSecrets: any RemoteRelaySecretStoring = KeychainRemoteRelaySecretStore()
  ) {
    self.preferences = preferences
    self.remoteSecrets = remoteSecrets
    pinnedProjectIDs = Set(preferences.stringArray(forKey: PreferenceKey.pinnedProjectIDs) ?? [])
    unreadThreadIDs = Set(preferences.stringArray(forKey: PreferenceKey.unreadThreadIDs) ?? [])
    hiddenThreadIDs = Set(preferences.stringArray(forKey: PreferenceKey.hiddenThreadIDs) ?? [])
    threadDrafts =
      preferences.dictionary(forKey: PreferenceKey.threadDrafts) as? [String: String]
      ?? [:]
    observedThreadUpdates =
      preferences.dictionary(forKey: PreferenceKey.observedThreadUpdates) as? [String: Double]
      ?? [:]
    focusPinnedOnly = preferences.bool(forKey: PreferenceKey.focusPinnedOnly)
    connectionPreference =
      preferences.string(forKey: PreferenceKey.connectionPreference)
      .flatMap(ConnectionPreference.init(rawValue:)) ?? .automatic
    remoteURL = preferences.string(forKey: PreferenceKey.remoteURL) ?? ""
    remoteChannelID = preferences.string(forKey: PreferenceKey.remoteChannelID) ?? ""
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
    if let configuration = Self.loadRemoteConfiguration(
      from: preferences, remoteSecrets: remoteSecrets)
    {
      remoteConfigured = true
      self.client.configureRemote(configuration)
    }
    if let provisioningURL = Self.provisioningURL(from: arguments) {
      do {
        try loadRemoteProvisioning(from: provisioningURL)
        try FileManager.default.removeItem(at: provisioningURL)
      } catch {
        presentedError = BridgeError(
          code: "remote_provisioning", message: error.localizedDescription, recoverable: true)
      }
    }
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

  var unreadCount: Int { unreadThreadIDs.subtracting(hiddenThreadIDs).count }
  var draftCount: Int { Set(threadDrafts.keys).subtracting(hiddenThreadIDs).count }

  var hiddenThreads: [ThreadSummary] {
    projects.flatMap(\.threads)
      .filter { hiddenThreadIDs.contains($0.id) }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  var hiddenThreadCount: Int { hiddenThreads.count }

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

  func saveRemoteConnection() {
    do {
      guard let url = URL(string: remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)),
        let channelID = UUID(
          uuidString: remoteChannelID.trimmingCharacters(in: .whitespacesAndNewlines)),
        let token = Data(base64Encoded: remoteToken.trimmingCharacters(in: .whitespacesAndNewlines))
          ?? remoteSecrets.load()
      else { throw RemoteRelayError.invalidResponse }
      let credential = try RelayChannelCredential(channelID: channelID, token: token)
      let configuration = try RemoteRelayConfiguration(baseURL: url, credential: credential)
      try applyRemoteConfiguration(configuration)
    } catch {
      presentedError = BridgeError(
        code: "remote_configuration", message: error.localizedDescription, recoverable: true)
    }
  }

  func importRemoteConnection(from url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      try loadRemoteProvisioning(from: url)
    } catch {
      presentedError = BridgeError(
        code: "remote_provisioning", message: error.localizedDescription, recoverable: true)
    }
  }

  func removeRemoteConnection() {
    client.configureRemote(nil)
    remoteSecrets.remove()
    preferences.removeObject(forKey: PreferenceKey.remoteURL)
    preferences.removeObject(forKey: PreferenceKey.remoteChannelID)
    remoteURL = ""
    remoteChannelID = ""
    remoteToken = ""
    remoteConfigured = false
    if connectionPreference == .remoteOnly { connectionPreference = .automatic }
  }

  func refresh(threadID: String? = nil) {
    guard isPaired else { return }
    send(.refresh(RefreshRequest(threadID: threadID)))
  }

  func isProjectPinned(_ projectID: String) -> Bool {
    pinnedProjectIDs.contains(projectID)
  }

  func isThreadUnread(_ threadID: String) -> Bool {
    unreadThreadIDs.contains(threadID) && !hiddenThreadIDs.contains(threadID)
  }

  func unreadCount(in threads: [ThreadSummary]) -> Int {
    threads.lazy.filter { self.isThreadUnread($0.id) }.count
  }

  func isThreadHidden(_ threadID: String) -> Bool {
    hiddenThreadIDs.contains(threadID)
  }

  func hideThread(_ threadID: String) {
    hiddenThreadIDs.insert(threadID)
    markThreadRead(threadID)
    persistHiddenThreads()
  }

  func unhideThread(_ threadID: String) {
    hiddenThreadIDs.remove(threadID)
    persistHiddenThreads()
  }

  func unhideAllThreads() {
    hiddenThreadIDs.removeAll()
    persistHiddenThreads()
  }

  func draft(for threadID: String) -> String {
    threadDrafts[threadID] ?? ""
  }

  func hasDraft(_ threadID: String) -> Bool {
    !(threadDrafts[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  func updateDraft(_ text: String, for threadID: String) {
    if text.isEmpty {
      threadDrafts.removeValue(forKey: threadID)
    } else {
      threadDrafts[threadID] = text
    }
    preferences.set(threadDrafts, forKey: PreferenceKey.threadDrafts)
  }

  func clearDraft(for threadID: String) {
    threadDrafts.removeValue(forKey: threadID)
    preferences.set(threadDrafts, forKey: PreferenceKey.threadDrafts)
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
    visibleThreadID = thread.id
    markThreadRead(thread.id)
    if demoMode {
      #if DEBUG
        threadDetail = DemoFixtures.threadDetail
      #endif
      return
    }
    if threadDetail?.thread.id != thread.id { threadDetail = nil }
    selectedThreadID = thread.id
    send(.subscribe(ThreadSubscription(threadID: thread.id)))
  }

  func closeThread(threadID: String) {
    guard visibleThreadID == threadID else { return }
    visibleThreadID = nil
  }

  func dismissUnreadNotification() {
    unreadNotification = nil
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

  func setModel(_ model: String, for threadID: String) {
    guard let detail = threadDetail, detail.thread.id == threadID,
      detail.thread.controlLevel != .observe,
      detail.availableModels.contains(where: { $0.id == model }),
      detail.selectedModel != model
    else { return }
    isUpdatingModel = true
    pendingModelUpdate = (threadID, detail.selectedModel)
    threadDetail = ThreadDetail(
      thread: detail.thread,
      timeline: detail.timeline,
      pendingActions: detail.pendingActions,
      selectedModel: model,
      availableModels: detail.availableModels,
      refreshedAt: detail.refreshedAt
    )
    if !send(.setThreadModel(SetThreadModelRequest(threadID: threadID, model: model))) {
      isUpdatingModel = false
      pendingModelUpdate = nil
      threadDetail = detail
    }
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
      applyWorkspace(snapshot)
      pendingWorkspaceID = nil
      pendingWorkspacePages = [:]
    case .workspacePage(let page):
      receive(page)
    case .threadDetail(let detail):
      let reconciled = reconcileOptimisticMessages(in: detail)
      threadDetail = reconciled
      if visibleThreadID == detail.thread.id { markThreadRead(detail.thread.id) }
      rememberActivity(in: reconciled)
      isSending = false
      if pendingModelUpdate?.threadID == detail.thread.id {
        pendingModelUpdate = nil
        isUpdatingModel = false
      }
    case .timelineEvent(let item):
      mergeTimelineEvent(item)
    case .analytics(let snapshot):
      let phone = latestPhoneSample?.telemetry ?? snapshot.phone
      analytics = AnalyticsSnapshot(phone: phone, mac: snapshot.mac, link: analytics.link)
      if let mac = snapshot.mac { appendHistory(mac, to: &macHistory) }
    case .pong(let pong):
      receive(pong)
    case .error(let error):
      let wasUpdatingModel = isUpdatingModel
      if wasUpdatingModel,
        let pendingModelUpdate,
        let detail = threadDetail,
        detail.thread.id == pendingModelUpdate.threadID
      {
        threadDetail = ThreadDetail(
          thread: detail.thread,
          timeline: detail.timeline,
          pendingActions: detail.pendingActions,
          selectedModel: pendingModelUpdate.previousModel,
          availableModels: detail.availableModels,
          refreshedAt: detail.refreshedAt
        )
      }
      if !wasUpdatingModel, let selectedThreadID {
        markLatestOptimisticMessageFailed(threadID: selectedThreadID)
      }
      isSending = false
      isUpdatingModel = false
      pendingModelUpdate = nil
      if error.code == "pairing_required" { isPaired = false }
      presentedError = error
    case .clientHello, .pair, .refresh, .subscribe, .sendMessage, .setThreadModel, .interrupt,
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
    applyWorkspace(snapshot)
    pendingWorkspaceID = nil
    pendingWorkspacePages = [:]
  }

  private func applyWorkspace(_ snapshot: WorkspaceSnapshot) {
    let hadWorkspace = workspace != nil || !observedThreadUpdates.isEmpty
    let stabilized = WorkspaceOrderStabilizer.apply(snapshot, preserving: workspace)
    let threads = stabilized.projects.flatMap(\.threads)
    let validIDs = Set(threads.map(\.id))
    var newestUnread: ThreadSummary?

    for thread in threads {
      let timestamp = thread.updatedAt.timeIntervalSince1970
      let previous = observedThreadUpdates[thread.id]
      let isNewActivity = previous.map { timestamp > $0 + 0.001 } ?? hadWorkspace
      if isNewActivity, visibleThreadID != thread.id, !hiddenThreadIDs.contains(thread.id) {
        unreadThreadIDs.insert(thread.id)
        if newestUnread == nil || thread.updatedAt > newestUnread!.updatedAt {
          newestUnread = thread
        }
      }
      observedThreadUpdates[thread.id] = max(previous ?? timestamp, timestamp)
      if visibleThreadID == thread.id { unreadThreadIDs.remove(thread.id) }
    }

    unreadThreadIDs.formIntersection(validIDs)
    hiddenThreadIDs.formIntersection(validIDs)
    observedThreadUpdates = observedThreadUpdates.filter { validIDs.contains($0.key) }
    persistUnreadState()
    persistHiddenThreads()
    workspace = stabilized
    if let newestUnread {
      unreadNotification = ThreadUnreadNotification(
        threadID: newestUnread.id,
        title: newestUnread.title,
        detail: newestUnread.status == .waiting ? "Waiting for you" : "New thread activity"
      )
    }
  }

  private func mergeTimelineEvent(_ item: TimelineItem) {
    let timestamp = item.timestamp.timeIntervalSince1970
    observedThreadUpdates[item.threadID] = max(
      observedThreadUpdates[item.threadID] ?? timestamp,
      timestamp
    )
    if hiddenThreadIDs.contains(item.threadID) {
      markThreadRead(item.threadID)
    } else if visibleThreadID != item.threadID {
      markThreadUnread(item.threadID, detail: item.title)
    } else {
      markThreadRead(item.threadID)
    }
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

    timeline = TimelineEventReducer.merge(item, into: timeline)

    detail = ThreadDetail(
      thread: detail.thread,
      timeline: timeline,
      pendingActions: detail.pendingActions,
      selectedModel: detail.selectedModel,
      availableModels: detail.availableModels,
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
      selectedModel: detail.selectedModel,
      availableModels: detail.availableModels,
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
        assistantPhase: item.assistantPhase,
        timestamp: item.timestamp
      )
    }
    optimisticMessages[detail.thread.id] = acknowledged
    return ThreadDetail(
      thread: detail.thread,
      timeline: detail.timeline + acknowledged,
      pendingActions: detail.pendingActions,
      selectedModel: detail.selectedModel,
      availableModels: detail.availableModels,
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
      assistantPhase: items[last].assistantPhase,
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
      selectedModel: detail.selectedModel,
      availableModels: detail.availableModels,
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
    static let unreadThreadIDs = "eng.unread-thread-ids"
    static let hiddenThreadIDs = "eng.hidden-thread-ids"
    static let observedThreadUpdates = "eng.observed-thread-updates"
    static let threadDrafts = "eng.thread-drafts"
    static let remoteURL = "eng.remote-url"
    static let remoteChannelID = "eng.remote-channel-id"
  }

  private func loadRemoteProvisioning(from url: URL) throws {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let document = try JSONDecoder().decode(RelayProvisioningDocument.self, from: data)
    try applyRemoteConfiguration(document.configuration())
  }

  private func applyRemoteConfiguration(_ configuration: RemoteRelayConfiguration) throws {
    try remoteSecrets.save(configuration.credential.token)
    preferences.set(configuration.baseURL.absoluteString, forKey: PreferenceKey.remoteURL)
    preferences.set(
      configuration.credential.channelID.uuidString, forKey: PreferenceKey.remoteChannelID)
    remoteURL = configuration.baseURL.absoluteString
    remoteChannelID = configuration.credential.channelID.uuidString
    remoteToken = ""
    remoteConfigured = true
    client.configureRemote(configuration)
  }

  private static func provisioningURL(from arguments: [String]) -> URL? {
    guard let index = arguments.firstIndex(of: "-eng-relay-provision"),
      arguments.indices.contains(index + 1)
    else { return nil }
    let path = arguments[index + 1]
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appending(path: path)
  }

  private static func loadRemoteConfiguration(
    from preferences: UserDefaults,
    remoteSecrets: any RemoteRelaySecretStoring
  ) -> RemoteRelayConfiguration? {
    guard let value = preferences.string(forKey: PreferenceKey.remoteURL),
      let url = URL(string: value),
      let channel = preferences.string(forKey: PreferenceKey.remoteChannelID),
      let channelID = UUID(uuidString: channel),
      let token = remoteSecrets.load(),
      let credential = try? RelayChannelCredential(channelID: channelID, token: token)
    else { return nil }
    return try? RemoteRelayConfiguration(baseURL: url, credential: credential)
  }

  private func markThreadUnread(_ threadID: String, detail: String) {
    unreadThreadIDs.insert(threadID)
    persistUnreadState()
    let title = projects.flatMap(\.threads).first { $0.id == threadID }?.title ?? "Codex thread"
    unreadNotification = ThreadUnreadNotification(
      threadID: threadID,
      title: title,
      detail: detail.isEmpty ? "New thread activity" : detail
    )
  }

  private func markThreadRead(_ threadID: String) {
    unreadThreadIDs.remove(threadID)
    if unreadNotification?.threadID == threadID { unreadNotification = nil }
    persistUnreadState()
  }

  private func persistUnreadState() {
    preferences.set(Array(unreadThreadIDs).sorted(), forKey: PreferenceKey.unreadThreadIDs)
    preferences.set(observedThreadUpdates, forKey: PreferenceKey.observedThreadUpdates)
  }

  private func persistHiddenThreads() {
    preferences.set(Array(hiddenThreadIDs).sorted(), forKey: PreferenceKey.hiddenThreadIDs)
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
      unreadThreadIDs = ["demo-waiting"]
      hiddenThreadIDs = ["demo-saved"]
      unreadNotification = ThreadUnreadNotification(
        threadID: "demo-waiting",
        title: "Review transport safeguards",
        detail: "Waiting for you"
      )
      threadDrafts[DemoFixtures.liveThread.id] = "Remember to verify the keyboard transition"
    #endif
  }
}
