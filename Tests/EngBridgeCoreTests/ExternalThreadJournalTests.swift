import EngCore
import Foundation
import Testing

@testable import EngBridgeCore

struct ExternalThreadJournalTests {
  @Test func readerStreamsOnlyAllowlistedVisibleEventsAndTracksTheTurn() async throws {
    let threadID = UUID().uuidString.lowercased()
    let root = FileManager.default.temporaryDirectory.appending(
      path: "eng-journal-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let journal = root.appending(path: "rollout-test-\(threadID).jsonl")
    let initial: [JSONValue] = [
      [
        "type": "session_meta",
        "payload": ["id": .string(threadID), "base_instructions": "must stay on Mac"],
      ],
      event(["type": "task_started", "turn_id": "turn-1"]),
      event(
        completed(
          threadID: threadID,
          turnID: "turn-1",
          item: [
            "type": "UserMessage", "id": "user-1",
            "content": [["type": "text", "text": "Run the tests"]],
          ]
        )),
      event(
        completed(
          threadID: threadID,
          turnID: "turn-1",
          item: [
            "type": "AgentMessage", "id": "message-1", "phase": "commentary",
            "content": [["type": "Text", "text": "I’m checking the test suite."]],
          ]
        )),
      event(
        completed(
          threadID: threadID,
          turnID: "turn-1",
          item: [
            "type": "Reasoning", "id": "reasoning-1", "summary_text": [],
            "raw_content": ["private reasoning must stay on Mac"],
          ]
        )),
    ]
    try encodedLines(initial).write(to: journal)
    let reader = CodexSessionJournalReader(roots: [root])

    let first = await reader.observation(threadID: threadID)

    #expect(first.activeTurnID == "turn-1")
    #expect(first.turnStateKnown)
    #expect(first.timeline.map(\.id) == ["user-1", "message-1"])
    #expect(first.timeline.last?.assistantPhase == .commentary)
    #expect(!first.timeline.map(\.body).joined().contains("private reasoning"))
    #expect(!first.timeline.map(\.body).joined().contains("must stay on Mac"))

    let appended: [JSONValue] = [
      event(
        completed(
          threadID: threadID,
          turnID: "turn-1",
          item: [
            "type": "CommandExecution", "id": "command-1", "status": "completed",
            "parsed_cmd": [["cmd": "swift test"]], "stdout": "47 tests passed", "stderr": "",
          ]
        )),
      event(["type": "task_complete", "turn_id": "turn-1"]),
    ]
    let handle = try FileHandle(forWritingTo: journal)
    try handle.seekToEnd()
    try handle.write(contentsOf: encodedLines(appended))
    try handle.close()

    let second = await reader.observation(threadID: threadID)

    #expect(second.activeTurnID == nil)
    #expect(second.turnStateKnown)
    #expect(second.timeline.last?.id == "command-1")
    #expect(second.timeline.last?.title == "swift test")
    #expect(second.timeline.last?.body == "47 tests passed")
  }

  @Test func mapperRejectsOtherThreadsAndNonEventRecords() throws {
    let expected = UUID().uuidString.lowercased()
    let other = UUID().uuidString.lowercased()
    let otherThread = event(
      completed(
        threadID: other,
        turnID: "turn-1",
        item: [
          "type": "AgentMessage", "id": "message-1",
          "content": [["type": "Text", "text": "Not for this phone"]],
        ]
      ))
    let responseItem: JSONValue = [
      "type": "response_item",
      "payload": ["type": "reasoning", "encrypted_content": "secret"],
    ]

    #expect(
      CodexJournalMapper.map(try encode(otherThread), expectedThreadID: expected).item == nil)
    #expect(
      CodexJournalMapper.map(try encode(responseItem), expectedThreadID: expected).item == nil)
  }

  private func event(_ payload: JSONValue) -> JSONValue {
    ["timestamp": "2026-08-28T20:00:00.000Z", "type": "event_msg", "payload": payload]
  }

  private func completed(threadID: String, turnID: String, item: JSONValue) -> JSONValue {
    [
      "type": "item_completed",
      "thread_id": .string(threadID),
      "turn_id": .string(turnID),
      "item": item,
      "completed_at_ms": 1_787_947_200_000,
    ]
  }

  private func encodedLines(_ values: [JSONValue]) throws -> Data {
    var data = Data()
    for value in values {
      data.append(try encode(value))
      data.append(Data("\n".utf8))
    }
    return data
  }

  private func encode(_ value: JSONValue) throws -> Data {
    try JSONEncoder().encode(value)
  }
}
