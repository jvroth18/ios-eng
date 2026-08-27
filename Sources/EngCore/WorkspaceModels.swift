import Foundation

public enum ThreadControlLevel: String, Codable, CaseIterable, Equatable, Sendable {
  case observe
  case message
  case live
}

public enum ThreadRuntimeStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case active
  case waiting
  case idle
  case notLoaded
  case systemError
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
  public let bridgeName: String
  public let projects: [ProjectSummary]
  public let generatedAt: Date

  public init(bridgeName: String, projects: [ProjectSummary], generatedAt: Date = Date()) {
    self.bridgeName = bridgeName
    self.projects = projects
    self.generatedAt = generatedAt
  }
}

public struct ProjectSummary: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let repositoryRoot: String
  public let gitOrigin: String?
  public let threads: [ThreadSummary]
  public let updatedAt: Date

  public init(
    id: String,
    name: String,
    repositoryRoot: String,
    gitOrigin: String? = nil,
    threads: [ThreadSummary],
    updatedAt: Date
  ) {
    self.id = id
    self.name = name
    self.repositoryRoot = repositoryRoot
    self.gitOrigin = gitOrigin
    self.threads = threads
    self.updatedAt = updatedAt
  }

  public var activeThreadCount: Int {
    threads.filter { $0.status == .active || $0.status == .waiting }.count
  }
}

public struct ThreadSummary: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let preview: String
  public let cwd: String
  public let repositoryRoot: String
  public let source: String
  public let status: ThreadRuntimeStatus
  public let controlLevel: ThreadControlLevel
  public let activeTurnID: String?
  public let needsAttention: Bool
  public let updatedAt: Date

  public init(
    id: String,
    title: String,
    preview: String,
    cwd: String,
    repositoryRoot: String,
    source: String,
    status: ThreadRuntimeStatus,
    controlLevel: ThreadControlLevel,
    activeTurnID: String? = nil,
    needsAttention: Bool = false,
    updatedAt: Date
  ) {
    self.id = id
    self.title = title
    self.preview = preview
    self.cwd = cwd
    self.repositoryRoot = repositoryRoot
    self.source = source
    self.status = status
    self.controlLevel = controlLevel
    self.activeTurnID = activeTurnID
    self.needsAttention = needsAttention
    self.updatedAt = updatedAt
  }
}

public struct ThreadDetail: Codable, Equatable, Sendable {
  public let thread: ThreadSummary
  public let timeline: [TimelineItem]
  public let pendingActions: [PendingAction]
  public let refreshedAt: Date

  public init(
    thread: ThreadSummary,
    timeline: [TimelineItem],
    pendingActions: [PendingAction] = [],
    refreshedAt: Date = Date()
  ) {
    self.thread = thread
    self.timeline = timeline
    self.pendingActions = pendingActions
    self.refreshedAt = refreshedAt
  }
}

public enum TimelineKind: String, Codable, CaseIterable, Equatable, Sendable {
  case user
  case assistant
  case reasoning
  case plan
  case command
  case fileChange
  case tool
  case approval
  case system
  case error
}

public enum TimelineState: String, Codable, CaseIterable, Equatable, Sendable {
  case pending
  case running
  case completed
  case failed
  case interrupted
}

public struct TimelineItem: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let threadID: String
  public let turnID: String?
  public let kind: TimelineKind
  public let state: TimelineState
  public let title: String
  public let body: String
  public let timestamp: Date

  public init(
    id: String,
    threadID: String,
    turnID: String? = nil,
    kind: TimelineKind,
    state: TimelineState,
    title: String,
    body: String,
    timestamp: Date
  ) {
    self.id = id
    self.threadID = threadID
    self.turnID = turnID
    self.kind = kind
    self.state = state
    self.title = title
    self.body = body
    self.timestamp = timestamp
  }
}

public enum PendingActionKind: String, Codable, CaseIterable, Equatable, Sendable {
  case commandApproval
  case fileApproval
  case permissions
  case userInput
}

public struct PendingActionOption: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let label: String
  public let detail: String?

  public init(id: String, label: String, detail: String? = nil) {
    self.id = id
    self.label = label
    self.detail = detail
  }
}

public struct PendingAction: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let threadID: String
  public let kind: PendingActionKind
  public let title: String
  public let detail: String
  public let options: [PendingActionOption]
  public let createdAt: Date

  public init(
    id: String,
    threadID: String,
    kind: PendingActionKind,
    title: String,
    detail: String,
    options: [PendingActionOption],
    createdAt: Date = Date()
  ) {
    self.id = id
    self.threadID = threadID
    self.kind = kind
    self.title = title
    self.detail = detail
    self.options = options
    self.createdAt = createdAt
  }
}

public struct CodexThreadRecord: Equatable, Sendable {
  public let id: String
  public let name: String?
  public let preview: String
  public let cwd: String
  public let repositoryRoot: String?
  public let gitOrigin: String?
  public let source: String
  public let status: ThreadRuntimeStatus
  public let controlLevel: ThreadControlLevel
  public let activeTurnID: String?
  public let needsAttention: Bool
  public let updatedAt: Date

  public init(
    id: String,
    name: String? = nil,
    preview: String,
    cwd: String,
    repositoryRoot: String? = nil,
    gitOrigin: String? = nil,
    source: String,
    status: ThreadRuntimeStatus,
    controlLevel: ThreadControlLevel,
    activeTurnID: String? = nil,
    needsAttention: Bool = false,
    updatedAt: Date
  ) {
    self.id = id
    self.name = name
    self.preview = preview
    self.cwd = cwd
    self.repositoryRoot = repositoryRoot
    self.gitOrigin = gitOrigin
    self.source = source
    self.status = status
    self.controlLevel = controlLevel
    self.activeTurnID = activeTurnID
    self.needsAttention = needsAttention
    self.updatedAt = updatedAt
  }
}
