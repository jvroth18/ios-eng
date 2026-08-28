import EngCore
import Foundation

struct ThreadActivityPresentation: Equatable {
  let title: String
  let detail: String?
  let symbol: String
  let isActive: Bool

  static func current(
    thread: ThreadSummary,
    timeline: [TimelineItem],
    pendingActions: [PendingAction],
    isSending: Bool
  ) -> ThreadActivityPresentation? {
    if let action = pendingActions.first {
      return ThreadActivityPresentation(
        title: "Waiting for you",
        detail: action.title,
        symbol: "person.crop.circle.badge.questionmark",
        isActive: false
      )
    }

    if let item = timeline.last(where: {
      ($0.state == .running || $0.state == .pending) && $0.kind != .user
    }) {
      return activity(for: item)
    }

    if isSending || thread.activeTurnID != nil || thread.status == .active {
      return ThreadActivityPresentation(
        title: "Thinking",
        detail: nil,
        symbol: "brain",
        isActive: true
      )
    }

    if thread.status == .waiting {
      return ThreadActivityPresentation(
        title: "Waiting for you",
        detail: nil,
        symbol: "person.crop.circle.badge.questionmark",
        isActive: false
      )
    }

    return nil
  }

  private static func activity(for item: TimelineItem) -> ThreadActivityPresentation {
    switch item.kind {
    case .assistant:
      return ThreadActivityPresentation(
        title: "Writing response", detail: nil, symbol: "text.cursor", isActive: true)
    case .reasoning:
      return ThreadActivityPresentation(
        title: "Thinking", detail: nonempty(item.body), symbol: "brain", isActive: true)
    case .plan:
      return ThreadActivityPresentation(
        title: "Updating plan", detail: nil, symbol: "list.bullet.clipboard", isActive: true)
    case .command:
      return ThreadActivityPresentation(
        title: "Running command", detail: nonempty(item.title), symbol: "terminal", isActive: true)
    case .fileChange:
      return ThreadActivityPresentation(
        title: "Editing files", detail: nil, symbol: "doc.badge.gearshape", isActive: true)
    case .tool:
      return ThreadActivityPresentation(
        title: "Using tool", detail: nonempty(item.title), symbol: "wrench.and.screwdriver",
        isActive: true)
    case .approval:
      return ThreadActivityPresentation(
        title: "Waiting for approval", detail: nonempty(item.title), symbol: "hand.raised",
        isActive: false)
    case .system:
      return ThreadActivityPresentation(
        title: "Working", detail: nonempty(item.title), symbol: "gearshape.2", isActive: true)
    case .error:
      return ThreadActivityPresentation(
        title: "Error", detail: nonempty(item.body), symbol: "xmark.octagon.fill",
        isActive: false)
    case .user:
      return ThreadActivityPresentation(
        title: "Thinking", detail: nil, symbol: "brain", isActive: true)
    }
  }

  private static func nonempty(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : String(normalized.prefix(160))
  }
}
