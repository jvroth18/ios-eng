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

public struct WorkspacePage: Codable, Equatable, Sendable {
  public let snapshotID: UUID
  public let bridgeName: String
  public let projects: [ProjectSummary]
  public let generatedAt: Date
  public let pageIndex: Int
  public let pageCount: Int

  public init(
    snapshotID: UUID,
    bridgeName: String,
    projects: [ProjectSummary],
    generatedAt: Date,
    pageIndex: Int,
    pageCount: Int
  ) {
    self.snapshotID = snapshotID
    self.bridgeName = bridgeName
    self.projects = projects
    self.generatedAt = generatedAt
    self.pageIndex = pageIndex
    self.pageCount = pageCount
  }
}

public enum WorkspacePager {
  public static func pages(
    for snapshot: WorkspaceSnapshot,
    maxThreadsPerPage: Int = 100
  ) -> [WorkspacePage] {
    let capacity = max(1, maxThreadsPerPage)
    var drafts: [[ProjectSummary]] = []
    var current: [ProjectSummary] = []
    var currentThreadCount = 0

    func fragment(_ project: ProjectSummary, threads: [ThreadSummary]) -> ProjectSummary {
      ProjectSummary(
        id: project.id,
        name: project.name,
        repositoryRoot: project.repositoryRoot,
        gitOrigin: project.gitOrigin,
        threads: threads,
        updatedAt: project.updatedAt
      )
    }

    func flush() {
      guard !current.isEmpty else { return }
      drafts.append(current)
      current = []
      currentThreadCount = 0
    }

    for project in snapshot.projects {
      if project.threads.isEmpty {
        current.append(fragment(project, threads: []))
        if current.count >= capacity { flush() }
        continue
      }

      var offset = 0
      while offset < project.threads.count {
        if currentThreadCount == capacity { flush() }
        let count = min(capacity - currentThreadCount, project.threads.count - offset)
        let end = offset + count
        current.append(fragment(project, threads: Array(project.threads[offset..<end])))
        currentThreadCount += count
        offset = end
      }
    }
    flush()
    if drafts.isEmpty { drafts = [[]] }

    let snapshotID = UUID()
    return drafts.enumerated().map { index, projects in
      WorkspacePage(
        snapshotID: snapshotID,
        bridgeName: snapshot.bridgeName,
        projects: projects,
        generatedAt: snapshot.generatedAt,
        pageIndex: index,
        pageCount: drafts.count
      )
    }
  }

  public static func assemble(_ pages: [WorkspacePage]) -> WorkspaceSnapshot? {
    guard let first = pages.first,
      first.pageCount > 0,
      pages.count == first.pageCount,
      pages.allSatisfy({
        $0.snapshotID == first.snapshotID
          && $0.bridgeName == first.bridgeName
          && $0.generatedAt == first.generatedAt
          && $0.pageCount == first.pageCount
          && $0.pageIndex >= 0
          && $0.pageIndex < first.pageCount
      }),
      Set(pages.map(\.pageIndex)).count == first.pageCount
    else { return nil }

    var order: [String] = []
    var projects: [String: ProjectSummary] = [:]
    for page in pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
      for fragment in page.projects {
        if let existing = projects[fragment.id] {
          projects[fragment.id] = ProjectSummary(
            id: existing.id,
            name: existing.name,
            repositoryRoot: existing.repositoryRoot,
            gitOrigin: existing.gitOrigin ?? fragment.gitOrigin,
            threads: existing.threads + fragment.threads,
            updatedAt: max(existing.updatedAt, fragment.updatedAt)
          )
        } else {
          order.append(fragment.id)
          projects[fragment.id] = fragment
        }
      }
    }

    return WorkspaceSnapshot(
      bridgeName: first.bridgeName,
      projects: order.compactMap { projects[$0] },
      generatedAt: first.generatedAt
    )
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

public enum AssistantMessagePhase: String, Codable, CaseIterable, Equatable, Sendable {
  case commentary
  case finalAnswer = "final_answer"
}

public struct TimelineItem: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let threadID: String
  public let turnID: String?
  public let kind: TimelineKind
  public let state: TimelineState
  public let title: String
  public let body: String
  public let assistantPhase: AssistantMessagePhase?
  public let timestamp: Date

  public init(
    id: String,
    threadID: String,
    turnID: String? = nil,
    kind: TimelineKind,
    state: TimelineState,
    title: String,
    body: String,
    assistantPhase: AssistantMessagePhase? = nil,
    timestamp: Date
  ) {
    self.id = id
    self.threadID = threadID
    self.turnID = turnID
    self.kind = kind
    self.state = state
    self.title = title
    self.body = body
    self.assistantPhase = assistantPhase
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

public struct PendingQuestion: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let prompt: String
  public let options: [PendingActionOption]

  public init(id: String, prompt: String, options: [PendingActionOption] = []) {
    self.id = id
    self.prompt = prompt
    self.options = options
  }
}

public struct PendingAction: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let threadID: String
  public let kind: PendingActionKind
  public let title: String
  public let detail: String
  public let options: [PendingActionOption]
  public let questions: [PendingQuestion]
  public let createdAt: Date

  public init(
    id: String,
    threadID: String,
    kind: PendingActionKind,
    title: String,
    detail: String,
    options: [PendingActionOption],
    questions: [PendingQuestion] = [],
    createdAt: Date = Date()
  ) {
    self.id = id
    self.threadID = threadID
    self.kind = kind
    self.title = title
    self.detail = detail
    self.options = options
    self.questions = questions
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
