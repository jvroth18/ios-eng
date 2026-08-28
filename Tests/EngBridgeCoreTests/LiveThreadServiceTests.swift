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
    #expect(methods.contains("thread/resume"))
    #expect(!methods.contains("thread/start"))
    #expect(!methods.contains("thread/delete"))
    #expect(!methods.contains("thread/archive"))
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

  private static let activeTurn: JSONValue = [
    "id": "turn-1", "status": "inProgress", "items": [],
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
  private var responses: [String: [JSONValue]] = [:]
  private(set) var requestedMethods: [String] = []

  init() {
    events = AsyncStream { $0.finish() }
  }

  func enqueue(method: String, response: JSONValue) {
    responses[method, default: []].append(response)
  }

  func request(method: String, params: JSONValue) throws -> JSONValue {
    requestedMethods.append(method)
    guard var values = responses[method], !values.isEmpty else {
      throw AppServerFailure(message: "No mock response for \(method)")
    }
    let value = values.removeFirst()
    responses[method] = values
    return value
  }

  func respond(id: JSONValue, result: JSONValue) {}
}
