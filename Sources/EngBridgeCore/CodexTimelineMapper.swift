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
    let now = eventTimestamp(params) ?? Date()

    if method == "item/agentMessage/delta", let delta = params["delta"]?.stringValue {
      return TimelineItem(
        id: streamItemID(params, fallback: "agent:\(turnID ?? threadID)"),
        threadID: threadID,
        turnID: turnID,
        kind: .assistant,
        state: .running,
        title: "Codex",
        body: delta,
        timestamp: now
      )
    }

    if method == "item/commandExecution/outputDelta",
      let delta = params["delta"]?.stringValue
    {
      return streamingItem(
        kind: .command,
        title: "Command output",
        body: delta,
        itemID: params["itemId"]?.stringValue,
        threadID: threadID,
        turnID: turnID,
        now: now
      )
    }

    if method == "item/fileChange/outputDelta", let delta = params["delta"]?.stringValue {
      return streamingItem(
        kind: .fileChange,
        title: "File changes",
        body: delta,
        itemID: params["itemId"]?.stringValue,
        threadID: threadID,
        turnID: turnID,
        now: now
      )
    }

    if method == "item/plan/delta", let delta = params["delta"]?.stringValue {
      return streamingItem(
        kind: .plan,
        title: "Plan",
        body: delta,
        itemID: params["itemId"]?.stringValue,
        threadID: threadID,
        turnID: turnID,
        now: now
      )
    }

    if method == "item/reasoning/summaryTextDelta",
      let delta = params["delta"]?.stringValue
    {
      return TimelineItem(
        id: streamItemID(params, fallback: "reasoning:\(turnID ?? threadID)"),
        threadID: threadID,
        turnID: turnID,
        kind: .reasoning,
        state: .running,
        title: "Thinking",
        body: delta,
        timestamp: now
      )
    }

    if method == "turn/plan/updated" {
      let explanation = params["explanation"]?.stringValue
      let steps = planText(params["plan"])
      return TimelineItem(
        id: "turn-plan:\(turnID ?? threadID)",
        threadID: threadID,
        turnID: turnID,
        kind: .plan,
        state: .running,
        title: "Plan",
        body: [explanation, steps].compactMap { value in
          guard let value, !value.isEmpty else { return nil }
          return value
        }.joined(separator: "\n"),
        timestamp: now
      )
    }

    if method == "turn/diff/updated", let diff = params["diff"]?.stringValue {
      return TimelineItem(
        id: "turn-diff:\(turnID ?? threadID)",
        threadID: threadID,
        turnID: turnID,
        kind: .fileChange,
        state: .running,
        title: "Turn diff",
        body: diff,
        timestamp: now
      )
    }

    if method == "item/commandExecution/terminalInteraction",
      let input = params["stdin"]?.stringValue
    {
      return streamingItem(
        kind: .command,
        title: "Terminal input",
        body: "\n› \(input)",
        itemID: params["itemId"]?.stringValue,
        threadID: threadID,
        turnID: turnID,
        now: now
      )
    }

    if method == "item/fileChange/patchUpdated", let changes = params["changes"] {
      return streamingItem(
        kind: .fileChange,
        title: "File changes",
        body: changes.compactDescription(limit: 6_000),
        itemID: params["itemId"]?.stringValue,
        threadID: threadID,
        turnID: turnID,
        now: now
      )
    }

    if method == "item/mcpToolCall/progress",
      let message = params["message"]?.stringValue
    {
      return streamingItem(
        kind: .tool,
        title: "Tool progress",
        body: message,
        itemID: params["itemId"]?.stringValue,
        threadID: threadID,
        turnID: turnID,
        now: now
      )
    }

    if method == "thread/compacted" {
      return TimelineItem(
        id: "compaction:\(turnID ?? threadID)",
        threadID: threadID,
        turnID: turnID,
        kind: .system,
        state: .completed,
        title: "Context compacted",
        body: "Codex compacted earlier context to continue the thread.",
        timestamp: now
      )
    }

    if method == "item/started" || method == "item/completed", let item = params["item"] {
      return mapItem(
        item,
        fallbackID: "event:\(UUID().uuidString)",
        threadID: threadID,
        turnID: turnID,
        timestamp: now,
        forcedState: method == "item/started" ? .running : nil
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

  private static func streamingItem(
    kind: TimelineKind,
    title: String,
    body: String,
    itemID: String?,
    threadID: String,
    turnID: String?,
    now: Date
  ) -> TimelineItem {
    TimelineItem(
      id: itemID ?? "delta:\(kind.rawValue):\(turnID ?? threadID)",
      threadID: threadID,
      turnID: turnID,
      kind: kind,
      state: .running,
      title: title,
      body: body,
      timestamp: now
    )
  }

  private static func mapItem(
    _ item: JSONValue,
    fallbackID: String,
    threadID: String,
    turnID: String?,
    timestamp: Date,
    forcedState: TimelineState? = nil
  ) -> TimelineItem {
    let type = item["type"]?.stringValue ?? "activity"
    let id = item["id"]?.stringValue ?? fallbackID
    let state = forcedState ?? timelineState(item["status"]?.stringValue)

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
        assistantPhase: item["phase"]?.stringValue.flatMap(AssistantMessagePhase.init(rawValue:)),
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
        body: item["text"]?.stringValue ?? planText(item["items"]),
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
    case "mcpToolCall", "dynamicToolCall":
      let namespace = item["server"]?.stringValue ?? item["namespace"]?.stringValue
      let tool = item["tool"]?.stringValue ?? item["name"]?.stringValue ?? type
      let title = [namespace, tool].compactMap { $0 }.joined(separator: ".")
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: title,
        body: item["result"]?.compactDescription(limit: 2_000)
          ?? item["contentItems"]?.compactDescription(limit: 2_000)
          ?? item["arguments"]?.compactDescription(limit: 2_000) ?? "",
        timestamp: timestamp
      )
    case "collabAgentToolCall":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: readableTitle(item["tool"]?.stringValue ?? "Agent collaboration"),
        body: item["prompt"]?.stringValue
          ?? item["agentsStates"]?.compactDescription(limit: 2_000) ?? "",
        timestamp: timestamp
      )
    case "subAgentActivity":
      let kind = item["kind"]?.stringValue ?? "activity"
      let subAgentState: TimelineState =
        switch kind {
        case "completed": .completed
        case "interrupted": .interrupted
        default: .running
        }
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: subAgentState,
        title: "Agent \(readableTitle(kind).lowercased())",
        body: item["agentPath"]?.stringValue ?? item["agentThreadId"]?.stringValue ?? "",
        timestamp: timestamp
      )
    case "webSearch":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: "Web search",
        body: item["query"]?.stringValue ?? "",
        timestamp: timestamp
      )
    case "imageView":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: "Viewed image",
        body: item["path"]?.stringValue ?? "",
        timestamp: timestamp
      )
    case "imageGeneration":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: "Generating image",
        body: "",
        timestamp: timestamp
      )
    case "sleep":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .tool,
        state: state,
        title: "Waiting",
        body: item.compactDescription(limit: 1_000),
        timestamp: timestamp
      )
    case "contextCompaction":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .system,
        state: .completed,
        title: "Context compacted",
        body: "Codex compacted earlier context to continue the thread.",
        timestamp: timestamp
      )
    case "enteredReviewMode", "exitedReviewMode":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .system,
        state: state,
        title: type == "enteredReviewMode" ? "Review started" : "Review completed",
        body: item["review"]?.stringValue ?? "",
        timestamp: timestamp
      )
    case "hookPrompt":
      return TimelineItem(
        id: id,
        threadID: threadID,
        turnID: turnID,
        kind: .system,
        state: state,
        title: "Hook activity",
        body: "",
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

  private static func streamItemID(_ params: JSONValue, fallback: String) -> String {
    params["itemId"]?.stringValue ?? fallback
  }

  private static func eventTimestamp(_ params: JSONValue) -> Date? {
    let milliseconds = params["startedAtMs"]?.doubleValue ?? params["completedAtMs"]?.doubleValue
    return milliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) }
  }

  private static func date(fromEpoch value: Double?) -> Date? {
    value.map(Date.init(timeIntervalSince1970:))
  }
}
