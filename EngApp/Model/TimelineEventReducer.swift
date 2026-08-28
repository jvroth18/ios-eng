import EngCore

enum TimelineEventReducer {
  static func merge(_ item: TimelineItem, into timeline: [TimelineItem]) -> [TimelineItem] {
    var timeline = timeline

    if let index = timeline.firstIndex(where: { $0.id == item.id }) {
      let existing = timeline[index]
      if existing.state == .running, item.state == .running {
        timeline[index] = TimelineItem(
          id: existing.id,
          threadID: existing.threadID,
          turnID: existing.turnID ?? item.turnID,
          kind: item.kind,
          state: .running,
          title: preferredTitle(item.title, over: existing.title),
          body: appendDelta(item.body, to: existing.body),
          assistantPhase: item.assistantPhase ?? existing.assistantPhase,
          timestamp: existing.timestamp
        )
      } else {
        timeline[index] = item
      }
      return timeline
    }

    timeline.append(item)
    return timeline
  }

  private static func appendDelta(_ delta: String, to existing: String) -> String {
    guard !delta.isEmpty else { return existing }
    return existing + delta
  }

  private static func preferredTitle(_ candidate: String, over existing: String) -> String {
    guard !existing.isEmpty else { return candidate }
    let continuationTitles = [
      "Command output", "File changes", "Plan", "Terminal input", "Tool progress",
    ]
    return continuationTitles.contains(candidate) ? existing : candidate
  }
}
