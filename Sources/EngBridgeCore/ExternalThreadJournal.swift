import EngCore
import Foundation

public struct ExternalThreadObservation: Equatable, Sendable {
  public let timeline: [TimelineItem]
  public let activeTurnID: String?
  public let turnStateKnown: Bool

  public init(
    timeline: [TimelineItem] = [],
    activeTurnID: String? = nil,
    turnStateKnown: Bool = false
  ) {
    self.timeline = timeline
    self.activeTurnID = activeTurnID
    self.turnStateKnown = turnStateKnown
  }
}

public protocol ExternalThreadObserving: Sendable {
  func observation(threadID: String) async -> ExternalThreadObservation
}

public actor CodexSessionJournalReader: ExternalThreadObserving {
  private struct State {
    let url: URL
    var offset: UInt64
    var remainder = Data()
    var timeline: [TimelineItem] = []
    var activeTurnID: String?
    var turnStateKnown = false
  }

  private static let initialReadBytes: UInt64 = 4 * 1_024 * 1_024
  private static let maximumTimelineItems = 120

  private let roots: [URL]
  private var states: [String: State] = [:]

  public init(
    codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
  ) {
    roots = [
      codexHome.appending(path: "sessions", directoryHint: .isDirectory),
      codexHome.appending(path: "archived_sessions", directoryHint: .isDirectory),
    ]
  }

  init(roots: [URL]) {
    self.roots = roots
  }

  public func observation(threadID: String) async -> ExternalThreadObservation {
    guard UUID(uuidString: threadID) != nil else { return ExternalThreadObservation() }
    do {
      var state = try state(for: threadID)
      try consumeAvailableBytes(into: &state, threadID: threadID)
      states[threadID] = state
      return ExternalThreadObservation(
        timeline: state.timeline,
        activeTurnID: state.activeTurnID,
        turnStateKnown: state.turnStateKnown
      )
    } catch {
      guard let state = states[threadID] else { return ExternalThreadObservation() }
      return ExternalThreadObservation(
        timeline: state.timeline,
        activeTurnID: state.activeTurnID,
        turnStateKnown: state.turnStateKnown
      )
    }
  }

  private func state(for threadID: String) throws -> State {
    if let state = states[threadID], FileManager.default.fileExists(atPath: state.url.path) {
      return state
    }
    guard let url = locateJournal(threadID: threadID) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let size = try fileSize(url)
    return State(url: url, offset: size > Self.initialReadBytes ? size - Self.initialReadBytes : 0)
  }

  private func consumeAvailableBytes(into state: inout State, threadID: String) throws {
    let size = try fileSize(state.url)
    if size < state.offset {
      state = State(url: state.url, offset: 0)
    }
    let handle = try FileHandle(forReadingFrom: state.url)
    defer { try? handle.close() }
    try handle.seek(toOffset: state.offset)
    let data = try handle.readToEnd() ?? Data()
    let wasPartialInitialRead =
      state.offset > 0 && state.timeline.isEmpty && state.remainder.isEmpty
    state.offset += UInt64(data.count)
    guard !data.isEmpty else { return }

    var combined = state.remainder
    combined.append(data)
    if wasPartialInitialRead, let firstNewline = combined.firstIndex(of: 0x0A) {
      combined.removeSubrange(combined.startIndex...firstNewline)
    }
    guard let finalNewline = combined.lastIndex(of: 0x0A) else {
      state.remainder = combined
      return
    }

    let complete = combined[combined.startIndex...finalNewline]
    state.remainder = Data(combined[combined.index(after: finalNewline)...])
    for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
      let update = CodexJournalMapper.map(Data(line), expectedThreadID: threadID)
      if let startedTurnID = update.startedTurnID {
        state.activeTurnID = startedTurnID
        state.turnStateKnown = true
      }
      if let completedTurnID = update.completedTurnID {
        state.turnStateKnown = true
        if state.activeTurnID == completedTurnID {
          state.activeTurnID = nil
        }
      }
      guard let item = update.item else { continue }
      if let index = state.timeline.firstIndex(where: { $0.id == item.id }) {
        state.timeline[index] = item
      } else {
        state.timeline.append(item)
      }
      if state.timeline.count > Self.maximumTimelineItems {
        state.timeline.removeFirst(state.timeline.count - Self.maximumTimelineItems)
      }
    }
  }

  private func locateJournal(threadID: String) -> URL? {
    let suffix = "-\(threadID).jsonl"
    var candidates: [URL] = []
    for root in roots where FileManager.default.fileExists(atPath: root.path) {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else { continue }
      for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(suffix) {
        candidates.append(url)
      }
    }
    return candidates.max { lhs, rhs in
      modificationDate(lhs) < modificationDate(rhs)
    }
  }

  private func modificationDate(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast
  }

  private func fileSize(_ url: URL) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
  }
}

struct CodexJournalUpdate: Equatable, Sendable {
  let item: TimelineItem?
  let startedTurnID: String?
  let completedTurnID: String?

  init(
    item: TimelineItem? = nil,
    startedTurnID: String? = nil,
    completedTurnID: String? = nil
  ) {
    self.item = item
    self.startedTurnID = startedTurnID
    self.completedTurnID = completedTurnID
  }
}

enum CodexJournalMapper {
  static func map(_ data: Data, expectedThreadID: String) -> CodexJournalUpdate {
    guard
      let root = try? JSONDecoder().decode(JSONValue.self, from: data),
      root["type"]?.stringValue == "event_msg",
      let payload = root["payload"],
      let eventType = payload["type"]?.stringValue
    else { return CodexJournalUpdate() }

    if eventType == "task_started" {
      return CodexJournalUpdate(startedTurnID: payload["turn_id"]?.stringValue)
    }
    if eventType == "task_complete" || eventType == "turn_aborted" {
      return CodexJournalUpdate(completedTurnID: payload["turn_id"]?.stringValue)
    }
    guard eventType == "item_completed",
      payload["thread_id"]?.stringValue == expectedThreadID,
      let item = payload["item"]
    else { return CodexJournalUpdate() }

    return CodexJournalUpdate(item: mapItem(item, payload: payload, root: root))
  }

  private static func mapItem(
    _ item: JSONValue,
    payload: JSONValue,
    root: JSONValue
  ) -> TimelineItem? {
    guard let threadID = payload["thread_id"]?.stringValue,
      let itemID = item["id"]?.stringValue,
      let type = item["type"]?.stringValue
    else { return nil }
    let turnID = payload["turn_id"]?.stringValue
    let timestamp = journalTimestamp(payload: payload, root: root)

    switch type {
    case "UserMessage":
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .user, title: "You",
        body: textContent(item["content"]), timestamp: timestamp)
    case "AgentMessage":
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .assistant, title: "Codex",
        body: textContent(item["content"]),
        assistantPhase: item["phase"]?.stringValue.flatMap(AssistantMessagePhase.init(rawValue:)),
        timestamp: timestamp)
    case "Reasoning":
      let summary = textContent(item["summary_text"])
      guard !summary.isEmpty else { return nil }
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .reasoning,
        title: "Thinking", body: summary, timestamp: timestamp)
    case "CommandExecution":
      let command =
        item["parsed_cmd"]?.arrayValue?.first?["cmd"]?.stringValue
        ?? textContent(item["command"], separator: " ")
      let output = [item["stdout"]?.stringValue, item["stderr"]?.stringValue]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .command,
        state: timelineState(item["status"]?.stringValue), title: command,
        body: output, timestamp: timestamp)
    case "FileChange":
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .fileChange,
        state: timelineState(item["status"]?.stringValue), title: "File changes",
        body: item["changes"]?.compactDescription(limit: 12_000) ?? "", timestamp: timestamp)
    case "McpToolCall":
      let title = [item["server"]?.stringValue, item["tool"]?.stringValue]
        .compactMap { $0 }.joined(separator: ".")
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .tool,
        state: timelineState(item["status"]?.stringValue), title: title,
        body: item["result"]?.compactDescription(limit: 12_000)
          ?? item["arguments"]?.compactDescription(limit: 12_000) ?? "",
        timestamp: timestamp)
    case "ContextCompaction":
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .system,
        title: "Context compacted",
        body: "Codex compacted earlier context to continue the thread.", timestamp: timestamp)
    case "ImageView":
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .tool,
        title: "Viewed image", body: item["path"]?.stringValue ?? "", timestamp: timestamp)
    case "Extension":
      let kind = item["kind"]?.stringValue ?? "Extension"
      let isWebSearch = kind == "web.search"
      return timelineItem(
        id: itemID, threadID: threadID, turnID: turnID, kind: .tool,
        title: isWebSearch ? "Web search" : readableTitle(kind),
        body: item["query"]?.stringValue ?? "", timestamp: timestamp)
    default:
      return nil
    }
  }

  private static func timelineItem(
    id: String,
    threadID: String,
    turnID: String?,
    kind: TimelineKind,
    state: TimelineState = .completed,
    title: String,
    body: String,
    assistantPhase: AssistantMessagePhase? = nil,
    timestamp: Date
  ) -> TimelineItem {
    TimelineItem(
      id: id,
      threadID: threadID,
      turnID: turnID,
      kind: kind,
      state: state,
      title: bounded(title, limit: 1_000),
      body: bounded(body, limit: 12_000),
      assistantPhase: assistantPhase,
      timestamp: timestamp
    )
  }

  private static func timelineState(_ value: String?) -> TimelineState {
    switch value {
    case "inProgress", "in_progress", "running": .running
    case "failed": .failed
    case "interrupted", "cancelled": .interrupted
    case "pending": .pending
    default: .completed
    }
  }

  private static func textContent(_ value: JSONValue?, separator: String = "\n") -> String {
    guard let value else { return "" }
    if let text = value.stringValue { return text }
    return (value.arrayValue ?? []).compactMap { entry in
      entry["text"]?.stringValue ?? entry.stringValue
    }.joined(separator: separator)
  }

  private static func journalTimestamp(payload: JSONValue, root: JSONValue) -> Date {
    if let milliseconds = payload["completed_at_ms"]?.doubleValue {
      return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
    if let value = root["timestamp"]?.stringValue,
      let date = ISO8601DateFormatter().date(from: value)
    {
      return date
    }
    return Date()
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    return String(value.prefix(limit)) + "…"
  }

  private static func readableTitle(_ value: String) -> String {
    value
      .replacingOccurrences(of: ".", with: " ")
      .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
      .capitalized
  }
}
