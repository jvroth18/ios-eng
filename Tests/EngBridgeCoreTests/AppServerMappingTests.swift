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
            "phase": "final_answer",
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
    #expect(result.items[2].assistantPhase == .finalAnswer)
  }

  @Test func mapsStreamingAgentDelta() throws {
    let item = try #require(
      CodexTimelineMapper.mapEvent(
        method: "item/agentMessage/delta",
        params: [
          "threadId": "thread-1",
          "turnId": "turn-1",
          "itemId": "agent-1",
          "delta": "Half of a streamed answer",
        ]
      )
    )
    #expect(item.kind == .assistant)
    #expect(item.state == .running)
    #expect(item.id == "agent-1")
    #expect(item.body == "Half of a streamed answer")
  }

  @Test func mapsStartedCommentaryAsTheRunningStableItem() throws {
    let item = try #require(
      CodexTimelineMapper.mapEvent(
        method: "item/started",
        params: [
          "threadId": "thread-1",
          "turnId": "turn-1",
          "item": [
            "type": "agentMessage", "id": "agent-1", "text": "", "phase": "commentary",
          ],
        ]
      )
    )
    #expect(item.id == "agent-1")
    #expect(item.state == .running)
    #expect(item.assistantPhase == .commentary)
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
          params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-1",
            "delta": "chunk",
          ]
        )
      )
      #expect(item.kind == kind)
      #expect(item.state == .running)
      #expect(item.id == "item-1")
      #expect(item.body == "chunk")
    }
  }

  @Test func exposesReasoningSummariesButNotPrivateReasoningText() throws {
    let summary = try #require(
      CodexTimelineMapper.mapEvent(
        method: "item/reasoning/summaryTextDelta",
        params: [
          "threadId": "thread-1", "turnId": "turn-1", "itemId": "reasoning-1",
          "delta": "Inspecting the bridge logs",
        ]
      )
    )
    #expect(summary.id == "reasoning-1")
    #expect(summary.kind == .reasoning)
    #expect(
      CodexTimelineMapper.mapEvent(
        method: "item/reasoning/textDelta",
        params: [
          "threadId": "thread-1", "turnId": "turn-1", "itemId": "reasoning-1",
          "delta": "private model reasoning",
        ]
      ) == nil)
  }

  @Test func mapsPlanDiffTerminalToolAndCompactionNotifications() throws {
    let plan = try #require(
      CodexTimelineMapper.mapEvent(
        method: "turn/plan/updated",
        params: [
          "threadId": "thread-1", "turnId": "turn-1", "explanation": "Validation plan",
          "plan": [
            ["step": "Inspect", "status": "completed"],
            ["step": "Test", "status": "inProgress"],
          ],
        ]
      )
    )
    #expect(plan.id == "turn-plan:turn-1")
    #expect(plan.body == "Validation plan\n✓ Inspect\n• Test")

    let diff = try #require(
      CodexTimelineMapper.mapEvent(
        method: "turn/diff/updated",
        params: ["threadId": "thread-1", "turnId": "turn-1", "diff": "+fixed"]
      )
    )
    #expect(diff.id == "turn-diff:turn-1")
    #expect(diff.kind == .fileChange)

    let terminal = try #require(
      CodexTimelineMapper.mapEvent(
        method: "item/commandExecution/terminalInteraction",
        params: [
          "threadId": "thread-1", "turnId": "turn-1", "itemId": "command-1",
          "stdin": "yes\n",
        ]
      )
    )
    #expect(terminal.id == "command-1")
    #expect(terminal.body == "\n› yes\n")

    let progress = try #require(
      CodexTimelineMapper.mapEvent(
        method: "item/mcpToolCall/progress",
        params: [
          "threadId": "thread-1", "turnId": "turn-1", "itemId": "tool-1",
          "message": "Loading results",
        ]
      )
    )
    #expect(progress.id == "tool-1")
    #expect(progress.kind == .tool)

    let compaction = try #require(
      CodexTimelineMapper.mapEvent(
        method: "thread/compacted",
        params: ["threadId": "thread-1", "turnId": "turn-1"]
      )
    )
    #expect(compaction.kind == .system)
    #expect(compaction.title == "Context compacted")
  }

  @Test func mapsEveryStructuredTerminalActivityWithoutRawFallbackText() throws {
    let items: [(JSONValue, TimelineKind, String)] = [
      (
        [
          "type": "mcpToolCall", "id": "tool-1", "server": "github", "tool": "status",
          "status": "inProgress", "arguments": ["repo": "ios-eng"],
        ], .tool, "github.status"
      ),
      (
        [
          "type": "subAgentActivity", "id": "agent-1", "kind": "started",
          "agentPath": "/root/tester",
        ], .tool, "Agent started"
      ),
      (
        ["type": "webSearch", "id": "search-1", "query": "Codex App Server"], .tool,
        "Web search"
      ),
      (["type": "contextCompaction", "id": "compact-1"], .system, "Context compacted"),
    ]

    for (index, expected) in items.enumerated() {
      let turn: JSONValue = [
        "id": .string("turn-\(index)"), "status": "completed", "startedAt": 1_700_000_000,
        "items": [expected.0],
      ]
      let mapped = CodexTimelineMapper.mapTurns([turn], threadID: "thread-1")
      let item = try #require(mapped.items.first)
      #expect(item.kind == expected.1)
      #expect(item.title == expected.2)
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
