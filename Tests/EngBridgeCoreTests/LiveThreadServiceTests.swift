import EngCore
import Foundation
import Testing

@testable import EngBridgeCore

struct LiveThreadServiceTests {
  @Test func selectingExistingThreadResumesAndSubscribesWithoutCreatingThread() async throws {
    let client = MockAppServerClient()
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil]
    )
    await client.enqueue(
      method: "thread/resume",
      response: ["thread": ["id": "thread-1", "turns": [Self.activeTurn]]]
    )
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    let service = CodexThreadService(connection: client, bridgeName: "Test Mac")

    let workspace = try await service.refreshWorkspace()
    #expect(workspace.projects.flatMap(\.threads).first?.controlLevel == .message)
    let detail = try await service.subscribe(threadID: "thread-1")

    #expect(detail.thread.controlLevel == .live)
    #expect(detail.thread.activeTurnID == "turn-1")
    let methods = await client.requestedMethods
    let turnsRequest = await client.requestedRequests.first { $0.method == "thread/turns/list" }
    #expect(methods.contains("thread/resume"))
    #expect(turnsRequest?.params["itemsView"]?.stringValue == "summary")
    #expect(!methods.contains("thread/start"))
    #expect(!methods.contains("thread/delete"))
    #expect(!methods.contains("thread/archive"))
  }

  @Test func activeWriterStillOpensAsAReadableMacLiveThread() async throws {
    let client = MockAppServerClient()
    let external = MockExternalThreadController()
    let observedCommand = TimelineItem(
      id: "command-live",
      threadID: "thread-1",
      turnID: "turn-journal",
      kind: .command,
      state: .completed,
      title: "swift test",
      body: "47 tests passed",
      timestamp: Date(timeIntervalSince1970: 1_700_000_001)
    )
    let observer = MockExternalThreadObserver(
      value: ExternalThreadObservation(
        timeline: [observedCommand], activeTurnID: "turn-journal", turnStateKnown: true))
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil]
    )
    await client.enqueueFailure(
      method: "thread/resume",
      failure: AppServerFailure(
        code: -32_600,
        message: "thread thread-1 already has an active writer"
      ))
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    let service = CodexThreadService(
      connection: client,
      externalController: external,
      externalObserver: observer,
      bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    let detail = try await service.subscribe(threadID: "thread-1")

    #expect(detail.thread.controlLevel == .observe)
    #expect(detail.thread.activeTurnID == "turn-journal")
    #expect(detail.timeline.contains(where: { $0.id == "command-live" }))
    #expect(!(await service.isSubscribed(threadID: "thread-1")))
  }

  @Test func loadedExternalWriterIsProbedOnceInsteadOfOnEveryRefresh() async throws {
    let client = MockAppServerClient()
    await client.enqueue(method: "thread/loaded/list", response: ["data": ["thread-1"]])
    await client.enqueueFailure(
      method: "thread/resume",
      failure: AppServerFailure(
        code: -32_600, message: "thread thread-1 already has an active writer"))
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil])
    await client.enqueue(method: "thread/loaded/list", response: ["data": ["thread-1"]])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil])
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    let service = CodexThreadService(connection: client, bridgeName: "Test Mac")

    let first = try await service.refreshWorkspace()
    let second = try await service.refreshWorkspace()
    let detail = try await service.subscribe(threadID: "thread-1")

    #expect(first.projects.flatMap(\.threads).first?.controlLevel == .observe)
    #expect(second.projects.flatMap(\.threads).first?.controlLevel == .observe)
    #expect(detail.thread.controlLevel == .observe)
    #expect(await client.requestedMethods.filter { $0 == "thread/resume" }.count == 1)
  }

  @Test func activeWriterMessagesQueueIntoTheOwningMacSession() async throws {
    let client = MockAppServerClient()
    let external = MockExternalThreadController()
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil]
    )
    await client.enqueueFailure(
      method: "thread/resume",
      failure: AppServerFailure(
        code: -32_600, message: "thread thread-1 already has an active writer"))
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    let service = CodexThreadService(
      connection: client, externalController: external, bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    _ = try await service.subscribe(threadID: "thread-1")
    #expect(
      try await service.sendMessage(threadID: "thread-1", text: "Continue safely") == "turn-1")
    #expect(await external.queuedMessages == ["thread-1:Continue safely"])
    #expect(!(await client.requestedMethods.contains("turn/steer")))
  }

  @Test func activeWriterStopTargetsTheOwningMacSession() async throws {
    let client = MockAppServerClient()
    let external = MockExternalThreadController()
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil]
    )
    await client.enqueueFailure(
      method: "thread/resume",
      failure: AppServerFailure(
        code: -32_600, message: "thread thread-1 already has an active writer"))
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    let service = CodexThreadService(
      connection: client, externalController: external, bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    _ = try await service.subscribe(threadID: "thread-1")
    try await service.interrupt(threadID: "thread-1", turnID: "turn-1")
    #expect(await external.interruptedThreads == ["thread-1"])
    #expect(!(await client.requestedMethods.contains("turn/interrupt")))
  }

  @Test func recoveryResumesEveryDesiredPhoneSubscription() async throws {
    let client = MockAppServerClient()
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "idle")], "nextCursor": nil]
    )
    await client.enqueue(method: "thread/resume", response: ["thread": ["turns": []]])
    await client.enqueue(method: "thread/turns/list", response: ["data": []])
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(method: "thread/resume", response: ["thread": ["turns": []]])
    let service = CodexThreadService(connection: client, bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    _ = try await service.subscribe(threadID: "thread-1")
    try await service.recoverSubscriptions()

    #expect(await client.requestedMethods.filter { $0 == "thread/resume" }.count == 2)
    #expect(await service.isSubscribed(threadID: "thread-1"))
  }

  @Test func notificationStateTracksActiveTurnLifecycle() async throws {
    let client = MockAppServerClient()
    await client.enqueue(method: "thread/loaded/list", response: ["data": ["thread-1"]])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "idle")], "nextCursor": nil]
    )
    await client.enqueue(method: "thread/resume", response: ["thread": ["turns": []]])
    await client.enqueue(method: "thread/turns/list", response: ["data": []])
    let service = CodexThreadService(connection: client, bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    _ = try await service.subscribe(threadID: "thread-1")
    await service.recordNotification(
      method: "turn/started",
      params: ["threadId": "thread-1", "turn": ["id": "turn-live"]]
    )
    await client.enqueue(
      method: "thread/turns/list",
      response: [
        "data": [
          ["id": "turn-live", "status": "inProgress", "items": []]
        ]
      ]
    )
    #expect(try await service.threadDetail(threadID: "thread-1").thread.activeTurnID == "turn-live")

    await service.recordNotification(
      method: "turn/completed",
      params: ["threadId": "thread-1", "turn": ["id": "turn-live", "status": "completed"]]
    )
  }

  @Test func messageSteersActiveExistingTurnWithoutCreatingThread() async throws {
    let client = MockAppServerClient()
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "active")], "nextCursor": nil]
    )
    await client.enqueue(
      method: "thread/resume",
      response: ["thread": ["id": "thread-1", "turns": [Self.activeTurn]]]
    )
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    await client.enqueue(method: "thread/turns/list", response: ["data": [Self.activeTurn]])
    await client.enqueue(method: "turn/steer", response: ["turnId": "turn-1"])
    let service = CodexThreadService(connection: client, bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    _ = try await service.subscribe(threadID: "thread-1")
    #expect(try await service.sendMessage(threadID: "thread-1", text: "Steer") == "turn-1")
    let methods = await client.requestedMethods
    #expect(methods.contains("turn/steer"))
    #expect(!methods.contains("turn/start"))
    #expect(!methods.contains("thread/start"))
  }

  @Test func messageStartsTurnInsideIdleExistingThreadWithoutCreatingThread() async throws {
    let client = MockAppServerClient()
    await client.enqueue(method: "thread/loaded/list", response: ["data": []])
    await client.enqueue(
      method: "thread/list",
      response: ["data": [Self.thread(status: "idle")], "nextCursor": nil]
    )
    await client.enqueue(method: "thread/resume", response: ["thread": ["turns": []]])
    await client.enqueue(method: "thread/turns/list", response: ["data": []])
    await client.enqueue(method: "thread/turns/list", response: ["data": []])
    await client.enqueue(method: "turn/start", response: ["turn": ["id": "turn-new"]])
    let service = CodexThreadService(connection: client, bridgeName: "Test Mac")

    _ = try await service.refreshWorkspace()
    _ = try await service.subscribe(threadID: "thread-1")
    #expect(try await service.sendMessage(threadID: "thread-1", text: "Continue") == "turn-new")
    let methods = await client.requestedMethods
    #expect(methods.contains("turn/start"))
    #expect(!methods.contains("thread/start"))
    #expect(!methods.contains("thread/delete"))
  }

  private static let activeTurn: JSONValue = [
    "id": "turn-1", "status": "inProgress",
    "items": [
      ["type": "agentMessage", "id": "message-1", "text": "Working on the Mac"]
    ],
  ]

  private static func thread(status: String) -> JSONValue {
    [
      "id": "thread-1",
      "cwd": "/tmp/project",
      "preview": "Existing conversation",
      "source": "cli",
      "updatedAt": 1_700_000_000,
      "status": ["type": .string(status), "activeFlags": []],
    ]
  }
}

private actor MockAppServerClient: AppServerClient {
  nonisolated let events: AsyncStream<AppServerInbound>
  private var responses: [String: [Result<JSONValue, AppServerFailure>]] = [:]
  private(set) var requestedMethods: [String] = []
  private(set) var requestedRequests: [(method: String, params: JSONValue)] = []

  init() {
    events = AsyncStream { $0.finish() }
  }

  func enqueue(method: String, response: JSONValue) {
    responses[method, default: []].append(.success(response))
  }

  func enqueueFailure(method: String, failure: AppServerFailure) {
    responses[method, default: []].append(.failure(failure))
  }

  func request(method: String, params: JSONValue) throws -> JSONValue {
    requestedMethods.append(method)
    requestedRequests.append((method, params))
    guard var values = responses[method], !values.isEmpty else {
      throw AppServerFailure(message: "No mock response for \(method)")
    }
    let result = values.removeFirst()
    responses[method] = values
    return try result.get()
  }

  func respond(id: JSONValue, result: JSONValue) {}
}

private actor MockExternalThreadController: ExternalThreadControlling {
  private(set) var queuedMessages: [String] = []
  private(set) var interruptedThreads: [String] = []

  func queue(threadID: String, message: String) {
    queuedMessages.append("\(threadID):\(message)")
  }

  func interrupt(threadID: String) {
    interruptedThreads.append(threadID)
  }
}

private struct MockExternalThreadObserver: ExternalThreadObserving {
  let value: ExternalThreadObservation

  func observation(threadID: String) async -> ExternalThreadObservation { value }
}
