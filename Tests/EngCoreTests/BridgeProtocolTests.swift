import Foundation
import Testing

@testable import EngCore

struct BridgeProtocolTests {
  @Test func workspaceSnapshotRoundTripsWithStableEnvelopeShape() throws {
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    let thread = ThreadSummary(
      id: "thread-1",
      title: "Build the phone mirror",
      preview: "Build the phone mirror",
      cwd: "/Users/jordan/Testing/ios-eng",
      repositoryRoot: "/Users/jordan/Testing/ios-eng",
      source: "cli",
      status: .active,
      controlLevel: .live,
      activeTurnID: "turn-1",
      updatedAt: now
    )
    let project = ProjectSummary(
      id: "project-1",
      name: "ios-eng",
      repositoryRoot: thread.repositoryRoot,
      threads: [thread],
      updatedAt: now
    )
    let expected = BridgeEnvelope(
      id: UUID(uuidString: "A9EA0BBA-568D-4C8E-A1F1-2278434F36F3")!,
      sentAt: now,
      message: .workspaceSnapshot(
        WorkspaceSnapshot(bridgeName: "Jordan's MacBook", projects: [project], generatedAt: now)
      )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(expected)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let message = try #require(object["message"] as? [String: Any])
    #expect(message["kind"] as? String == "workspaceSnapshot")
    #expect(message["payload"] != nil)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(BridgeEnvelope.self, from: data) == expected)
  }

  @Test func everyCommandPayloadRoundTrips() throws {
    let deviceID = UUID(uuidString: "417CB15A-7F55-43C5-B911-39C3BBC9D8A7")!
    let messages: [BridgeMessage] = [
      .clientHello(ClientHello(deviceID: deviceID, deviceName: "iPhone", appVersion: "1.0")),
      .pair(PairRequest(code: "123456", deviceID: deviceID, deviceName: "iPhone")),
      .refresh(RefreshRequest(threadID: "thread-1")),
      .subscribe(ThreadSubscription(threadID: "thread-1")),
      .sendMessage(SendMessageRequest(threadID: "thread-1", text: "Continue")),
      .interrupt(InterruptRequest(threadID: "thread-1", turnID: "turn-1")),
      .approvalResponse(ApprovalResponse(requestID: "rpc-1", decision: .acceptForSession)),
      .userInputResponse(UserInputResponse(requestID: "rpc-2", answers: ["choice": "yes"])),
      .ping(Ping(sequence: 7, clientSentAt: .distantPast, payloadBytes: 65_536)),
      .error(BridgeError(code: "test", message: "Expected", recoverable: true)),
    ]

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for message in messages {
      let encoded = try encoder.encode(BridgeEnvelope(message: message))
      let decoded = try decoder.decode(BridgeEnvelope.self, from: encoded)
      #expect(decoded.message == message)
    }
  }

  @Test func outgoingTextIsNormalizedWithoutMutatingOriginal() {
    let request = SendMessageRequest(threadID: "thread-1", text: "  Continue from the phone. \n")
    #expect(request.text == "  Continue from the phone. \n")
    #expect(request.normalizedText == "Continue from the phone.")
  }
}
