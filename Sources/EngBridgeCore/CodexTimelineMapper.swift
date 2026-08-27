import EngCore
import Foundation

public enum CodexTimelineMapper {
  public struct Result: Equatable, Sendable {
    public let items: [TimelineItem]
    public let activeTurnID: String?

    public init(items: [TimelineItem], activeTurnID: String?) {
      self.items = items
      self.activeTurnID = activeTurnID
    }
  }

  public static func mapTurns(_ turns: [JSONValue], threadID: String) -> Result {
    var timeline: [TimelineItem] = []
    var activeTurnID: String?

    for turn in turns {
      let turnID = turn["id"]?.stringValue ?? "turn-unknown"
      let status = turn["status"]?.stringValue ?? "completed"
      if status == "inProgress" { activeTurnID = turnID }
      let timestamp = date(fromEpoch: turn["startedAt"]?.doubleValue) ?? .distantPast
      for (index, item) in (turn["items"]?.arrayValue ?? []).enumerated() {
        timeline.append(
          mapItem(
            item,
            fallbackID: "\(turnID):\(index)",
            threadID: threadID,
            turnID: turnID,
            timestamp: timestamp
          )
        )
      }
    }

    return Result(items: timeline, activeTurnID: activeTurnID)
  }

  public static func mapEvent(method: String, params: JSONValue) -> TimelineItem? {
    guard let threadID = params["threadId"]?.stringValue else { return nil }
    let turnID = params["turnId"]?.stringValue
    let now = Date()

    if method == "item/agentMessage/delta", let delta = params["delta"]?.stringValue {
      return TimelineItem(
        id: "delta:\(turnID ?? threadID):\(now.timeIntervalSince1970)",
        threadID: threadID,
        turnID: turnID,
        kind: .assistant,
        state: .running,
        title: "Codex",
        body: delta,
        timestamp: now
      )
    }

    if method.contains("reasoning"), let delta = params["delta"]?.stringValue {
      return TimelineItem(
        id: "reasoning:\(turnID ?? threadID):\(now.timeIntervalSince1970)",
        threadID: threadID,
        turnID: turnID,
        kind: .reasoning,
        state: .running,
        title: "Thinking",
        body: delta,
        timestamp: now
      )
    }

    if method == "item/started" || method == "item/completed", let item = params["item"] {
      return mapItem(
        item,
        fallbackID: "event:\(UUID().uuidString)",
        threadID: threadID,
        turnID: turnID,
        timestamp: now
      )
    }

    if method == "error" || method.hasSuffix("/error") {
      return TimelineItem(
        id: "error:\(UUID().uuidString)",
        threadID: threadID,
        turnID: turnID,
        kind: .error,
        state: .failed,
        title: "Codex error",
        body: params["message"]?.stringValue ?? params.compactDescription(),
        timestamp: now
      )
    }

    return nil
  }

  private static func mapItem(
    _ item: JSONValue,
    fallbackID: String,
    threadID: String,
    turnID: String?,
    timestamp: Date
  ) -> TimelineItem {
    let type = item["type"]?.stringValue ?? "activity"
    let id = item["id"]?.stringValue ?? fallbackID
    let state = timelineState(item["status"]?.stringValue)

    switch type {
    case "userMessage":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .user,
        state: .completed,
        title: "You",
        body: textContent(item["content"]) ?? "",
        timestamp: timestamp
      )
    case "agentMessage":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .assistant,
        state: state,
        title: "Codex",
        body: item["text"]?.stringValue ?? textContent(item["content"]) ?? "",
        timestamp: timestamp
      )
    case "reasoning":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .reasoning,
        state: state,
        title: "Thinking",
        body: textContent(item["summary"]) ?? item["text"]?.stringValue ?? "",
        timestamp: timestamp
      )
    case "plan":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .plan,
        state: state,
        title: "Plan",
        body: planText(item["items"]),
        timestamp: timestamp
      )
    case "commandExecution":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .command,
        state: state,
        title: item["command"]?.stringValue ?? "Command",
        body: item["aggregatedOutput"]?.stringValue ?? item["output"]?.stringValue ?? "",
        timestamp: timestamp
      )
    case "fileChange":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .fileChange,
        state: state,
        title: "File changes",
        body: item["changes"]?.compactDescription(limit: 2_000) ?? "",
        timestamp: timestamp
      )
    case "mcpToolCall", "dynamicToolCall", "collabAgentToolCall", "webSearch":
      let tool = item["tool"]?.stringValue ?? item["name"]?.stringValue ?? type
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: tool,
        body: item["result"]?.compactDescription(limit: 2_000)
          ?? item["arguments"]?.compactDescription(limit: 2_000) ?? "",
        timestamp: timestamp
      )
    default:
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .system,
        state: state,
        title: readableTitle(type),
        body: item.compactDescription(limit: 1_500),
        timestamp: timestamp
      )
    }
  }

  private static func timelineState(_ value: String?) -> TimelineState {
    switch value {
    case "inProgress", "running": .running
    case "failed": .failed
    case "interrupted", "cancelled": .interrupted
    case "pending": .pending
    default: .completed
    }
  }

  private static func textContent(_ value: JSONValue?) -> String? {
    guard let value else { return nil }
    if let text = value.stringValue { return text }
    guard let array = value.arrayValue else { return nil }
    let parts = array.compactMap { entry in
      entry["text"]?.stringValue ?? entry.stringValue
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
  }

  private static func planText(_ value: JSONValue?) -> String {
    (value?.arrayValue ?? []).compactMap { entry in
      guard let step = entry["step"]?.stringValue else { return nil }
      let status = entry["status"]?.stringValue ?? "pending"
      return "\(status == "completed" ? "✓" : "•") \(step)"
    }.joined(separator: "\n")
  }

  private static func readableTitle(_ value: String) -> String {
    value
      .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
      .capitalized
  }

  private static func date(fromEpoch value: Double?) -> Date? {
    value.map(Date.init(timeIntervalSince1970:))
  }
}
