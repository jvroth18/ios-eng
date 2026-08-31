import EngCore
import Foundation
import Testing

@testable import Eng

/// Records outbound envelopes and lets a test inject inbound events without a radio.
final class FakeBridgeClient: BridgeClientTransport, @unchecked Sendable {
  let kind = BridgeTransportKind.nearbyAuto
  let identityPublicKey: Data?
  private let lock = NSLock()
  private var handler: (@Sendable (BridgeClientEvent) -> Void)?
  private var outbound: [BridgeEnvelope] = []
  private var preferences: [ConnectionPreference] = []
  private var remoteConfigurations: [RemoteRelayConfiguration?] = []

  var sent: [BridgeMessage] { lock.withLock { outbound.map(\.message) } }
  var appliedPreferences: [ConnectionPreference] { lock.withLock { preferences } }
  var appliedRemoteConfigurations: [RemoteRelayConfiguration?] {
    lock.withLock { remoteConfigurations }
  }

  init(identityPublicKey: Data? = nil) {
    self.identityPublicKey = identityPublicKey
  }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { self.handler = handler }
  }
  func start() {}
  func stop() {}
  func send(_ envelope: BridgeEnvelope) throws {
    lock.withLock { outbound.append(envelope) }
  }
  func setConnectionPreference(_ preference: ConnectionPreference) {
    lock.withLock { preferences.append(preference) }
  }
  func configureRemote(_ configuration: RemoteRelayConfiguration?) {
    lock.withLock { remoteConfigurations.append(configuration) }
  }

  func emit(_ event: BridgeClientEvent) {
    lock.withLock { handler }?(event)
  }
}

final class FakeRemoteRelaySecretStore: RemoteRelaySecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var token: Data?
  func load() -> Data? { lock.withLock { token } }
  func save(_ token: Data) { lock.withLock { self.token = token } }
  func remove() { lock.withLock { token = nil } }
}

@MainActor
struct BridgeStoreTests {
  private static let now = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func directLinkBearerLabelsAreHonest() {
    #expect(DirectLinkBearer.classify(interfaceType: .wiredEthernet) == .wired)
    #expect(DirectLinkBearer.classify(interfaceType: .wifi) == .wifi)
    #expect(DirectLinkBearer.classify(interfaceType: .other) == .other)
    #expect(DirectLinkBearer.wired.connectionName.contains("USB-C"))
  }

  @Test func activePathLabelUsesTheConnectedBearer() {
    let (store, _) = Self.makeStore()
    store.handleForTesting(.state(.connected("Mac · USB-C / Wired")))
    #expect(store.activePathLabel == "USB-C / Wired")
  }

  @Test func connectionPreferenceIsAppliedAndPersisted() {
    let defaults = Self.isolatedPreferences()
    let firstClient = FakeBridgeClient()
    let first = BridgeStore(client: firstClient, arguments: [], preferences: defaults)

    first.connectionPreference = .preferWiFi

    #expect(firstClient.appliedPreferences.last == .preferWiFi)
    let secondClient = FakeBridgeClient()
    let second = BridgeStore(client: secondClient, arguments: [], preferences: defaults)
    #expect(second.connectionPreference == .preferWiFi)
    #expect(secondClient.appliedPreferences.last == .preferWiFi)
  }

  @Test func deploymentArgumentOverridesAndPersistsConnectionPreference() {
    let defaults = Self.isolatedPreferences()
    let client = FakeBridgeClient()
    let store = BridgeStore(
      client: client,
      arguments: ["Eng", "-eng-connection-preference", ConnectionPreference.remoteOnly.rawValue],
      preferences: defaults)

    #expect(store.connectionPreference == .remoteOnly)
    #expect(client.appliedPreferences.last == .remoteOnly)
    #expect(
      defaults.string(forKey: "eng.connection-preference")
        == ConnectionPreference.remoteOnly.rawValue)
  }

  @Test func remoteConfigurationUsesValidatedFieldsAndCanBeRemoved() throws {
    let defaults = Self.isolatedPreferences()
    let client = FakeBridgeClient()
    let secrets = FakeRemoteRelaySecretStore()
    let store = BridgeStore(
      client: client, arguments: [], preferences: defaults, remoteSecrets: secrets)
    let credential = try RelayChannelCredential.generate()
    store.remoteURL = "https://relay.example.com"
    store.remoteChannelID = credential.channelID.uuidString
    store.remoteToken = credential.bearerToken

    store.saveRemoteConnection()

    #expect(store.remoteConfigured)
    #expect(store.remoteToken.isEmpty)
    #expect(client.appliedRemoteConfigurations.last!?.credential == credential)
    store.removeRemoteConnection()
    #expect(!store.remoteConfigured)
    #expect(client.appliedRemoteConfigurations.last! == nil)
  }

  @Test func remoteProvisioningFileImportsIntoKeychainAndTransport() throws {
    let defaults = Self.isolatedPreferences()
    let client = FakeBridgeClient()
    let secrets = FakeRemoteRelaySecretStore()
    let store = BridgeStore(
      client: client, arguments: [], preferences: defaults, remoteSecrets: secrets)
    let expected = try RemoteRelayConfiguration(
      baseURL: URL(string: "https://relay.example.com")!,
      credential: RelayChannelCredential.generate())
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "EngProvisioning-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "phone-channel.json")
    try JSONEncoder().encode(RelayProvisioningDocument(configuration: expected)).write(to: file)

    store.importRemoteConnection(from: file)

    #expect(store.remoteConfigured)
    #expect(store.remoteToken.isEmpty)
    #expect(secrets.load() == expected.credential.token)
    #expect(client.appliedRemoteConfigurations.last! == expected)
  }

  @Test func folderPinsAndPinnedOnlyFocusPersist() {
    let defaults = Self.isolatedPreferences()
    let first = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)

    first.toggleProjectPin("ios-eng")
    first.focusPinnedOnly = true

    let second = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    #expect(second.isProjectPinned("ios-eng"))
    #expect(second.focusPinnedOnly)
    second.toggleProjectPin("ios-eng")
    #expect(!second.isProjectPinned("ios-eng"))
  }

  @Test func activityFilterDefaultsToActiveAndPersists() {
    let defaults = Self.isolatedPreferences()
    let first = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    #expect(first.activityFilter == .active)

    first.activityFilter = .week

    let second = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    #expect(second.activityFilter == .week)
  }

  @Test func activityFilterControlsTheCompleteDisplayedWorkspace() {
    let (store, _) = Self.makeStore()
    let active = Self.thread("active", status: .active)
    let idle = Self.thread("idle", status: .idle)
    store.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([active, idle]))))

    #expect(store.displayedProjects.flatMap(\.threads).map(\.id) == ["active"])

    store.activityFilter = .all
    #expect(Set(store.displayedProjects.flatMap(\.threads).map(\.id)) == Set(["active", "idle"]))
  }

  @Test func perThreadDraftsPersistAndClearIndependently() {
    let defaults = Self.isolatedPreferences()
    let first = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)

    first.updateDraft("Message one", for: "t1")
    first.updateDraft("Message two", for: "t2")
    #expect(first.hasDraft("t1"))
    #expect(first.draftCount == 2)

    let second = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    #expect(second.draft(for: "t1") == "Message one")
    #expect(second.draft(for: "t2") == "Message two")

    second.clearDraft(for: "t1")
    #expect(!second.hasDraft("t1"))
    #expect(second.hasDraft("t2"))
  }

  @Test func hiddenThreadsPersistStayQuietAndCanBeRestored() {
    let defaults = Self.isolatedPreferences()
    let first = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    let t1 = Self.thread("t1")
    let t2 = Self.thread("t2")
    first.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([t1, t2]))))
    first.updateDraft("Hidden draft", for: "t1")
    first.updateDraft("Visible draft", for: "t2")

    first.hideThread("t1")
    first.receive(
      BridgeEnvelope(
        message: .workspaceSnapshot(
          Self.workspace([Self.thread("t1", updatedAt: Self.now.addingTimeInterval(10)), t2]))))

    #expect(first.isThreadHidden("t1"))
    #expect(first.hiddenThreadCount == 1)
    #expect(first.unreadCount == 0)
    #expect(first.unreadNotification == nil)
    #expect(first.draftCount == 1)
    #expect(first.draft(for: "t1") == "Hidden draft")

    let second = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    second.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([t1, t2]))))
    #expect(second.isThreadHidden("t1"))
    second.unhideThread("t1")
    #expect(!second.isThreadHidden("t1"))
    #expect(second.draftCount == 2)
  }

  private static func thread(
    _ id: String,
    updatedAt: Date = now,
    status: ThreadRuntimeStatus = .active
  ) -> ThreadSummary {
    ThreadSummary(
      id: id, title: "Thread \(id)", preview: "", cwd: "/tmp/\(id)", repositoryRoot: "/tmp/\(id)",
      source: "cli", status: status, controlLevel: .live,
      activeTurnID: status == .active ? "turn-\(id)" : nil,
      updatedAt: updatedAt)
  }

  private static func workspace(_ threads: [ThreadSummary]) -> WorkspaceSnapshot {
    WorkspaceSnapshot(
      bridgeName: "Mac",
      projects: [
        ProjectSummary(
          id: "project", name: "Project", repositoryRoot: "/tmp/project", threads: threads,
          updatedAt: threads.map(\.updatedAt).max() ?? now)
      ],
      generatedAt: now
    )
  }

  private static func item(
    _ id: String, thread: String = "t1", kind: TimelineKind = .assistant,
    state: TimelineState = .running, body: String
  ) -> TimelineItem {
    TimelineItem(
      id: id, threadID: thread, turnID: "turn-\(thread)", kind: kind, state: state,
      title: "Codex", body: body, timestamp: now)
  }

  private static func makeStore() -> (BridgeStore, FakeBridgeClient) {
    let client = FakeBridgeClient()
    let store = BridgeStore(client: client, arguments: [], preferences: isolatedPreferences())
    return (store, client)
  }

  private static func isolatedPreferences() -> UserDefaults {
    let name = "BridgeStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private static func pair(_ store: BridgeStore) {
    store.receive(
      BridgeEnvelope(message: .pairResult(PairResult(accepted: true, bridgeName: "Mac"))))
  }

  @Test func streamingDeltasCoalesceByStableItemID() {
    let (store, _) = Self.makeStore()
    let detail = ThreadDetail(thread: Self.thread("t1"), timeline: [])
    store.receive(BridgeEnvelope(message: .threadDetail(detail)))

    store.receive(BridgeEnvelope(message: .timelineEvent(Self.item("a1", body: "Hello"))))
    store.receive(BridgeEnvelope(message: .timelineEvent(Self.item("a1", body: ", world"))))

    let timeline = store.threadDetail?.timeline ?? []
    #expect(timeline.count == 1)
    #expect(timeline.first?.id == "a1")
    #expect(timeline.first?.body == "Hello, world")
    #expect(timeline.first?.state == .running)
  }

  @Test func selectedThreadActivityBecomesItsLiveProjectSummary() {
    let (store, _) = Self.makeStore()
    let thread = Self.thread("t1")
    let command = Self.item("c1", kind: .command, body: "Running tests")

    store.receive(
      BridgeEnvelope(
        message: .threadDetail(ThreadDetail(thread: thread, timeline: [command]))))

    #expect(store.currentActivitySummary(for: thread) == "Running command: Codex")
  }

  @Test func firstWorkspaceBaselinesThreadsThenBackgroundUpdatesBecomeUnread() {
    let (store, _) = Self.makeStore()
    let initial = Self.thread("t1")
    store.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([initial]))))

    #expect(store.unreadCount == 0)
    #expect(store.unreadNotification == nil)

    let updated = Self.thread("t1", updatedAt: Self.now.addingTimeInterval(10))
    store.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([updated]))))

    #expect(store.isThreadUnread("t1"))
    #expect(store.unreadCount(in: [updated]) == 1)
    #expect(store.unreadNotification?.threadID == "t1")
    #expect(store.unreadNotification?.detail == "New thread activity")
  }

  @Test func visibleThreadStaysReadUntilNewActivityArrivesAfterClosing() {
    let (store, _) = Self.makeStore()
    let initial = Self.thread("t1")
    store.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([initial]))))
    store.subscribe(to: initial)

    let updated = Self.thread("t1", updatedAt: Self.now.addingTimeInterval(10))
    store.receive(BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([updated]))))
    #expect(!store.isThreadUnread("t1"))

    store.closeThread(threadID: "t1")
    store.receive(
      BridgeEnvelope(
        message: .timelineEvent(Self.item("background-answer", body: "Done"))))
    #expect(store.isThreadUnread("t1"))
    #expect(store.unreadNotification?.detail == "Codex")

    store.subscribe(to: updated)
    #expect(!store.isThreadUnread("t1"))
    #expect(store.unreadNotification == nil)
  }

  @Test func unreadStatePersistsAcrossStoreInstances() {
    let defaults = Self.isolatedPreferences()
    let first = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    first.receive(
      BridgeEnvelope(message: .workspaceSnapshot(Self.workspace([Self.thread("t1")]))))
    first.receive(
      BridgeEnvelope(
        message: .workspaceSnapshot(
          Self.workspace([Self.thread("t1", updatedAt: Self.now.addingTimeInterval(10))]))))
    #expect(first.isThreadUnread("t1"))

    let second = BridgeStore(client: FakeBridgeClient(), arguments: [], preferences: defaults)
    #expect(second.isThreadUnread("t1"))
  }

  @Test func completedItemReplacesItsRunningVersionById() {
    let (store, _) = Self.makeStore()
    store.receive(
      BridgeEnvelope(message: .threadDetail(ThreadDetail(thread: Self.thread("t1"), timeline: []))))
    store.receive(BridgeEnvelope(message: .timelineEvent(Self.item("a1", body: "Working"))))
    store.receive(
      BridgeEnvelope(
        message: .timelineEvent(Self.item("a1", state: .completed, body: "Working. Done."))))

    let timeline = store.threadDetail?.timeline ?? []
    #expect(timeline.count == 1)
    #expect(timeline.first?.state == .completed)
    #expect(timeline.first?.body == "Working. Done.")
  }

  @Test func differentKindsAndThreadsDoNotCoalesce() {
    let (store, _) = Self.makeStore()
    store.receive(
      BridgeEnvelope(message: .threadDetail(ThreadDetail(thread: Self.thread("t1"), timeline: []))))
    store.receive(BridgeEnvelope(message: .timelineEvent(Self.item("a1", body: "text"))))
    store.receive(
      BridgeEnvelope(message: .timelineEvent(Self.item("c1", kind: .command, body: "ls"))))
    store.receive(
      BridgeEnvelope(message: .timelineEvent(Self.item("x1", thread: "other", body: "ignored"))))

    let timeline = store.threadDetail?.timeline ?? []
    #expect(timeline.map(\.id) == ["a1", "c1"])
  }

  @Test func outgoingMessageAppearsBeforeTheBridgeReplies() {
    let (store, client) = Self.makeStore()
    store.receive(
      BridgeEnvelope(message: .threadDetail(ThreadDetail(thread: Self.thread("t1"), timeline: []))))

    store.sendMessage("  Hello now  ", to: "t1")

    let item = store.threadDetail?.timeline.last
    #expect(item?.kind == .user)
    #expect(item?.body == "Hello now")
    #expect(item?.state == .pending)
    #expect(item?.id.hasPrefix("local:user:") == true)
    #expect(store.isSending)
    #expect(
      client.sent.contains {
        guard case .sendMessage(let request) = $0 else { return false }
        return request.threadID == "t1" && request.text == "Hello now"
      })
  }

  @Test func modelSelectionIsOptimisticAndRevertsWhenTheBridgeRejectsIt() {
    let (store, client) = Self.makeStore()
    let models = [
      CodexModelOption(
        id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol", description: "Frontier",
        isDefault: true),
      CodexModelOption(
        id: "gpt-5.6-terra", displayName: "GPT-5.6 Terra", description: "Balanced",
        isDefault: false),
    ]
    store.receive(
      BridgeEnvelope(
        message: .threadDetail(
          ThreadDetail(
            thread: Self.thread("t1"), timeline: [], selectedModel: "gpt-5.6-sol",
            availableModels: models))))

    store.setModel("gpt-5.6-terra", for: "t1")

    #expect(store.threadDetail?.selectedModel == "gpt-5.6-terra")
    #expect(store.isUpdatingModel)
    #expect(
      client.sent.contains {
        guard case .setThreadModel(let request) = $0 else { return false }
        return request.threadID == "t1" && request.model == "gpt-5.6-terra"
      })

    store.receive(
      BridgeEnvelope(
        message: .error(
          BridgeError(code: "model", message: "Unavailable", recoverable: true))))
    #expect(store.threadDetail?.selectedModel == "gpt-5.6-sol")
    #expect(!store.isUpdatingModel)
  }

  @Test func serverMessageReplacesItsOptimisticCopyWithoutDuplication() {
    let (store, _) = Self.makeStore()
    store.receive(
      BridgeEnvelope(message: .threadDetail(ThreadDetail(thread: Self.thread("t1"), timeline: []))))
    store.sendMessage("Hello now", to: "t1")
    let serverItem = TimelineItem(
      id: "server-user-1", threadID: "t1", turnID: "turn-t1", kind: .user,
      state: .completed, title: "You", body: "Hello now", timestamp: Date())

    store.receive(
      BridgeEnvelope(
        message: .threadDetail(
          ThreadDetail(thread: Self.thread("t1"), timeline: [serverItem]))))

    let userItems = store.threadDetail?.timeline.filter { $0.kind == .user } ?? []
    #expect(userItems.map(\.id) == ["server-user-1"])
    #expect(!store.isSending)
  }

  @Test func workspacePagesAssembleOnlyWhenComplete() {
    let (store, _) = Self.makeStore()
    let projects = (0..<40).map { index in
      ProjectSummary(
        id: "p\(index)", name: "Project \(index)", repositoryRoot: "/tmp/p\(index)",
        threads: (0..<12).map { Self.thread("p\(index)-\($0)") }, updatedAt: Self.now)
    }
    let snapshot = WorkspaceSnapshot(bridgeName: "Mac", projects: projects, generatedAt: Self.now)
    let pages = WorkspacePager.pages(for: snapshot)
    #expect(pages.count > 1)

    for page in pages.dropLast().reversed() {
      store.receive(BridgeEnvelope(message: .workspacePage(page)))
      #expect(store.workspace == nil)
    }
    store.receive(BridgeEnvelope(message: .workspacePage(pages.last!)))
    #expect(store.workspace?.projects == projects)
  }

  @Test func pongMeasuresLatencyAndGoodput() {
    let (store, client) = Self.makeStore()
    Self.pair(store)
    #expect(store.isPaired)

    store.sendPing()
    guard case .ping(let ping)? = client.sent.last else {
      Issue.record("expected a ping to be sent")
      return
    }
    #expect(ping.payloadBytes == 65_536)

    store.receive(
      BridgeEnvelope(
        message: .pong(
          Pong(
            sequence: ping.sequence + 99, clientSentAt: ping.clientSentAt,
            bridgeReceivedAt: Date(), payloadBytes: ping.payloadBytes))))
    #expect(store.analytics.link.roundTripMilliseconds == nil)

    store.receive(
      BridgeEnvelope(
        message: .pong(
          Pong(
            sequence: ping.sequence, clientSentAt: ping.clientSentAt,
            bridgeReceivedAt: Date(), payloadBytes: ping.payloadBytes))))
    let link = store.analytics.link
    #expect((link.roundTripMilliseconds ?? 0) > 0)
    #expect((link.measuredBytesPerSecond ?? 0) > 0)
    #expect(link.quality != .unavailable)
  }

  @Test func silentReconnectProbeRejectionDoesNotRaiseAnError() {
    let (store, client) = Self.makeStore()
    store.handleForTesting(.state(.connected("Mac")))
    #expect(
      client.sent.contains {
        if case .pair(let request) = $0 { request.code.isEmpty } else { false }
      })
    store.receive(
      BridgeEnvelope(
        message: .pairResult(
          PairResult(accepted: false, bridgeName: "Mac", reason: "Pairing code is incorrect"))))
    #expect(store.presentedError == nil)
    #expect(!store.isPaired)

    store.pairingCode = "123456"
    store.pair()
    store.receive(
      BridgeEnvelope(
        message: .pairResult(
          PairResult(accepted: false, bridgeName: "Mac", reason: "Pairing code is incorrect"))))
    #expect(store.presentedError?.message == "Pairing code is incorrect")
  }

  @Test func pairingRequiredErrorDropsPairedState() {
    let (store, _) = Self.makeStore()
    Self.pair(store)
    store.receive(
      BridgeEnvelope(
        message: .error(
          BridgeError(code: "pairing_required", message: "Enter the code", recoverable: true))))
    #expect(!store.isPaired)
    #expect(store.presentedError?.code == "pairing_required")
  }

  @Test func selectedExistingThreadIsResubscribedAfterTransportPairing() {
    let (store, client) = Self.makeStore()
    store.subscribe(to: Self.thread("t1"))
    Self.pair(store)

    let subscriptions = client.sent.compactMap { message -> String? in
      guard case .subscribe(let value) = message else { return nil }
      return value.threadID
    }
    #expect(subscriptions == ["t1", "t1"])
  }

  @Test func reopeningSameThreadPreservesItsTimelineDuringRefresh() {
    let (store, _) = Self.makeStore()
    let first = Self.thread("t1")
    store.receive(
      BridgeEnvelope(
        message: .threadDetail(
          ThreadDetail(thread: first, timeline: [Self.item("answer", body: "Ready")]))))

    store.subscribe(to: first)
    #expect(store.threadDetail?.timeline.first?.body == "Ready")

    store.subscribe(to: Self.thread("t2"))
    #expect(store.threadDetail == nil)
  }

  @Test func debugAutomaticPairingDoesNotFirstSendAnEmptyTrustedCode() async {
    let client = FakeBridgeClient()
    let store = BridgeStore(
      client: client, arguments: ["-eng-pair-code", "123456"],
      preferences: Self.isolatedPreferences())
    client.emit(.state(.connected("Mac")))
    await Task.yield()

    let codes = client.sent.compactMap { message -> String? in
      guard case .pair(let request) = message else { return nil }
      return request.code
    }
    #expect(codes == ["123456"])
    _ = store
  }

  @Test func trustedReconnectCarriesTheTransportIdentityKey() async {
    let identityKey = Data(repeating: 0x5A, count: 32)
    let client = FakeBridgeClient(identityPublicKey: identityKey)
    let store = BridgeStore(client: client, arguments: [], preferences: Self.isolatedPreferences())
    client.emit(.state(.connected("Mac")))
    await Task.yield()

    let requests = client.sent.compactMap { message -> PairRequest? in
      guard case .pair(let request) = message else { return nil }
      return request
    }
    #expect(requests.count == 1)
    #expect(requests.first?.code == "")
    #expect(requests.first?.identityPublicKey == identityKey)
    _ = store
  }
}
