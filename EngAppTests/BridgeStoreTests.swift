import EngCore
import Foundation
import Testing

@testable import Eng

/// Records outbound envelopes and lets a test inject inbound events without a radio.
final class FakeBridgeClient: BridgeClientTransport, @unchecked Sendable {
  let kind = BridgeTransportKind.nearbyAuto
  private let lock = NSLock()
  private var handler: (@Sendable (BridgeClientEvent) -> Void)?
  private var outbound: [BridgeEnvelope] = []

  var sent: [BridgeMessage] { lock.withLock { outbound.map(\.message) } }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { self.handler = handler }
  }
  func start() {}
  func stop() {}
  func send(_ envelope: BridgeEnvelope) throws {
    lock.withLock { outbound.append(envelope) }
  }

  func emit(_ event: BridgeClientEvent) {
    lock.withLock { handler }?(event)
  }
}

@MainActor
struct BridgeStoreTests {
  private static let now = Date(timeIntervalSince1970: 1_700_000_000)

  private static func thread(_ id: String) -> ThreadSummary {
    ThreadSummary(
      id: id, title: "Thread \(id)", preview: "", cwd: "/tmp/\(id)", repositoryRoot: "/tmp/\(id)",
      source: "cli", status: .active, controlLevel: .live, activeTurnID: "turn-\(id)",
      updatedAt: now)
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
    let store = BridgeStore(client: client, arguments: [])
    return (store, client)
  }

  private static func pair(_ store: BridgeStore) {
    store.receive(
      BridgeEnvelope(message: .pairResult(PairResult(accepted: true, bridgeName: "Mac"))))
  }

  @Test func streamingDeltasCoalesceIntoTheRunningItem() {
    let (store, _) = Self.makeStore()
    let detail = ThreadDetail(thread: Self.thread("t1"), timeline: [])
    store.receive(BridgeEnvelope(message: .threadDetail(detail)))

    store.receive(BridgeEnvelope(message: .timelineEvent(Self.item("a1", body: "Hello"))))
    store.receive(BridgeEnvelope(message: .timelineEvent(Self.item("a2", body: ", world"))))

    let timeline = store.threadDetail?.timeline ?? []
    #expect(timeline.count == 1)
    #expect(timeline.first?.id == "a1")
    #expect(timeline.first?.body == "Hello, world")
    #expect(timeline.first?.state == .running)
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

  @Test func debugAutomaticPairingDoesNotFirstSendAnEmptyTrustedCode() async {
    let client = FakeBridgeClient()
    let store = BridgeStore(client: client, arguments: ["-eng-pair-code", "123456"])
    client.emit(.state(.connected("Mac")))
    await Task.yield()

    let codes = client.sent.compactMap { message -> String? in
      guard case .pair(let request) = message else { return nil }
      return request.code
    }
    #expect(codes == ["123456"])
    _ = store
  }
}
