import EngCore
import Foundation
import Testing

@testable import EngBridgeCore

struct AppServerMappingTests {
  @Test func jsonValueRoundTripsNestedProtocolData() throws {
    let expected: JSONValue = [
      "thread": [
        "id": "thread-1",
        "active": true,
        "counts": [1, 2, 3],
        "optional": nil,
      ]
    ]
    let data = try JSONEncoder().encode(expected)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data) == expected)
  }

  @Test func mapsPersistedTurnsIntoAReadableTimeline() {
    let turns: [JSONValue] = [
      [
        "id": "turn-1",
        "status": "completed",
        "startedAt": 1_700_000_000,
        "items": [
          [
            "type": "userMessage",
            "id": "user-1",
            "content": [["type": "text", "text": "Run the tests"]],
          ],
          [
            "type": "commandExecution",
            "id": "command-1",
            "command": "swift test",
            "aggregatedOutput": "All tests passed",
            "status": "completed",
          ],
          [
            "type": "agentMessage",
            "id": "agent-1",
            "text": "Everything is green.",
            "status": "completed",
          ],
        ],
      ],
      [
        "id": "turn-2",
        "status": "inProgress",
        "startedAt": 1_700_000_100,
        "items": [],
      ],
    ]

    let result = CodexTimelineMapper.mapTurns(turns, threadID: "thread-1")
    #expect(result.activeTurnID == "turn-2")
    #expect(result.items.map(\.kind) == [.user, .command, .assistant])
    #expect(result.items[1].title == "swift test")
    #expect(result.items[2].body == "Everything is green.")
  }

  @Test func mapsStreamingAgentDelta() throws {
    let item = try #require(
      CodexTimelineMapper.mapEvent(
        method: "item/agentMessage/delta",
        params: [
          "threadId": "thread-1",
          "turnId": "turn-1",
          "delta": "Half of a streamed answer",
        ]
      )
    )
    #expect(item.kind == .assistant)
    #expect(item.state == .running)
    #expect(item.body == "Half of a streamed answer")
  }

  @Test func mapsCommandFileAndPlanStreamingDeltas() throws {
    let cases: [(String, TimelineKind)] = [
      ("item/commandExecution/outputDelta", .command),
      ("item/fileChange/outputDelta", .fileChange),
      ("item/plan/delta", .plan),
    ]
    for (method, kind) in cases {
      let item = try #require(
        CodexTimelineMapper.mapEvent(
          method: method,
          params: ["threadId": "thread-1", "turnId": "turn-1", "delta": "chunk"]
        )
      )
      #expect(item.kind == kind)
      #expect(item.state == .running)
      #expect(item.body == "chunk")
    }
  }

  @Test func preservesServerRequestIDForPhoneResponse() async throws {
    let service = CodexThreadService(connection: AppServerConnection(), bridgeName: "Test Mac")
    let action = try #require(
      await service.recordServerRequest(
        id: "rpc-42",
        method: "item/commandExecution/requestApproval",
        params: [
          "threadId": "thread-1",
          "turnId": "turn-1",
          "itemId": "item-1",
          "startedAtMs": 1_700_000_000_000,
          "command": "swift test",
          "reason": "Verify the bridge",
        ]
      )
    )
    #expect(action.id == "rpc-42")
    #expect(action.threadID == "thread-1")
    #expect(action.options.map(\.id).contains("acceptForSession"))
  }

  @Test func treatsLoadedThreadsAsDirectlyControllableWithoutLegacyCapabilityFlag() {
    #expect(
      CodexThreadService.directControlAvailable(
        statusType: "active", canAcceptDirectInput: false))
    #expect(
      CodexThreadService.directControlAvailable(
        statusType: "idle", canAcceptDirectInput: false))
    #expect(
      !CodexThreadService.directControlAvailable(
        statusType: "notLoaded", canAcceptDirectInput: false))
    #expect(
      CodexThreadService.directControlAvailable(
        statusType: "notLoaded", canAcceptDirectInput: true))
  }

  @Test func preservesChoiceAndFreeFormUserInputQuestions() async throws {
    let service = CodexThreadService(connection: AppServerConnection(), bridgeName: "Test Mac")
    let action = try #require(
      await service.recordServerRequest(
        id: "rpc-input",
        method: "item/tool/requestUserInput",
        params: [
          "threadId": "thread-1",
          "questions": [
            [
              "id": "environment",
              "header": "Target",
              "question": "Which environment?",
              "options": [
                ["label": "Staging", "description": "Use test data"],
                ["label": "Production", "description": "Use live data"],
              ],
            ],
            [
              "id": "note",
              "header": "Note",
              "question": "Add a note",
            ],
          ],
        ]
      )
    )
    #expect(action.questions.map(\.id) == ["environment", "note"])
    #expect(action.questions[0].options.map(\.label) == ["Staging", "Production"])
    #expect(action.questions[1].options.isEmpty)
  }
}
