import EngCore
import Foundation
import Testing

@testable import Eng

struct TimelineEventReducerTests {
  @Test func appendsDeltasToTheExactItemWithoutCombiningSiblingMessages() {
    let first = item(id: "message-1", body: "Checking ", phase: .commentary)
    let sibling = item(id: "message-2", body: "Answer ", phase: .finalAnswer)
    let firstDelta = item(id: "message-1", body: "logs", phase: nil)

    var timeline = TimelineEventReducer.merge(first, into: [])
    timeline = TimelineEventReducer.merge(sibling, into: timeline)
    timeline = TimelineEventReducer.merge(firstDelta, into: timeline)

    #expect(timeline.map(\.id) == ["message-1", "message-2"])
    #expect(timeline[0].body == "Checking logs")
    #expect(timeline[0].assistantPhase == .commentary)
    #expect(timeline[1].body == "Answer ")
  }

  @Test func completedItemReplacesItsRunningVersionInPlace() {
    let running = item(id: "message-1", body: "Part", phase: .finalAnswer)
    let completed = TimelineItem(
      id: "message-1",
      threadID: "thread-1",
      turnID: "turn-1",
      kind: .assistant,
      state: .completed,
      title: "Codex",
      body: "Part complete",
      assistantPhase: .finalAnswer,
      timestamp: Date(timeIntervalSince1970: 2)
    )

    let timeline = TimelineEventReducer.merge(completed, into: [running])

    #expect(timeline.count == 1)
    #expect(timeline[0] == completed)
  }

  private func item(
    id: String,
    body: String,
    phase: AssistantMessagePhase?
  ) -> TimelineItem {
    TimelineItem(
      id: id,
      threadID: "thread-1",
      turnID: "turn-1",
      kind: .assistant,
      state: .running,
      title: "Codex",
      body: body,
      assistantPhase: phase,
      timestamp: Date(timeIntervalSince1970: 1)
    )
  }
}
