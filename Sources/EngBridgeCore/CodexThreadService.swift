import EngCore
import Foundation

public actor CodexThreadService {
  private struct RawThread: Sendable {
    let value: JSONValue
    let directlyControllable: Bool
  }

  private struct PendingServerRequest: Sendable {
    let rpcID: JSONValue
    let method: String
    let params: JSONValue
    let action: PendingAction
  }

  public nonisolated var events: AsyncStream<AppServerInbound> { connection.events }

  private let connection: AppServerConnection
  private let resolver: GitRepositoryResolver
  private let bridgeName: String
  private var rawThreads: [String: RawThread] = [:]
  private var summaries: [String: ThreadSummary] = [:]
  private var liveThreadIDs = Set<String>()
  private var subscribedThreadIDs = Set<String>()
  private var activeTurnIDs: [String: String] = [:]
  private var pendingRequests: [String: PendingServerRequest] = [:]

  public init(
    connection: AppServerConnection,
    resolver: GitRepositoryResolver = GitRepositoryResolver(),
    bridgeName: String = Host.current().localizedName ?? "Mac"
  ) {
    self.connection = connection
    self.resolver = resolver
    self.bridgeName = bridgeName
  }

  public func refreshWorkspace(limit: Int? = nil) async throws -> WorkspaceSnapshot {
    var cursor: String?
    var collected: [JSONValue] = []

    repeat {
      let pageLimit = limit.map { min(max($0 - collected.count, 1), 100) } ?? 100
      var params: [String: JSONValue] = [
        "limit": .number(Double(pageLimit)),
        "sortKey": "updated_at",
        "sortDirection": "desc",
        "sourceKinds": ["cli", "vscode", "appServer", "exec", "unknown"],
      ]
      if let cursor { params["cursor"] = .string(cursor) }
      let response = try await connection.request(method: "thread/list", params: .object(params))
      collected.append(contentsOf: response["data"]?.arrayValue ?? [])
      cursor = response["nextCursor"]?.stringValue
    } while cursor != nil && (limit.map { collected.count < $0 } ?? true)

    var records: [CodexThreadRecord] = []
    let selected = limit.map { Array(collected.prefix($0)) } ?? collected
    for value in selected {
      guard let id = value["id"]?.stringValue,
        let cwd = value["cwd"]?.stringValue
      else { continue }
      let root = await resolver.repositoryRoot(for: cwd)
      let statusValue = value["status"]
      let activeFlags = statusValue?["activeFlags"]?.arrayValue?.compactMap(\.stringValue) ?? []
      let canAccept = value["canAcceptDirectInput"]?.boolValue == true
      let directlyControllable = Self.directControlAvailable(
        statusType: statusValue?["type"]?.stringValue,
        canAcceptDirectInput: canAccept
      )
      let status = Self.runtimeStatus(statusValue, activeFlags: activeFlags)
      let control: ThreadControlLevel =
        liveThreadIDs.contains(id) || directlyControllable ? .live : .message
      let updated = Date(timeIntervalSince1970: value["updatedAt"]?.doubleValue ?? 0)
      let record = CodexThreadRecord(
        id: id,
        name: value["name"]?.stringValue.map { String($0.prefix(240)) },
        preview: String((value["preview"]?.stringValue ?? "").prefix(800)),
        cwd: cwd,
        repositoryRoot: root,
        gitOrigin: value["gitInfo"]?["originUrl"]?.stringValue,
        source: value["source"]?.stringValue ?? "unknown",
        status: status,
        controlLevel: control,
        activeTurnID: activeTurnIDs[id],
        needsAttention: activeFlags.contains("waitingOnApproval")
          || activeFlags.contains("waitingOnUserInput"),
        updatedAt: updated
      )
      records.append(record)
      rawThreads[id] = RawThread(value: value, directlyControllable: directlyControllable)
    }

    let projects = ProjectGrouper.group(records)
    summaries = Dictionary(
      uniqueKeysWithValues: projects.flatMap(\.threads).map { ($0.id, $0) }
    )
    return WorkspaceSnapshot(bridgeName: bridgeName, projects: projects)
  }

  public func subscribe(threadID: String) async throws -> ThreadDetail {
    subscribedThreadIDs.insert(threadID)
    return try await threadDetail(threadID: threadID)
  }

  public func threadDetail(threadID: String) async throws -> ThreadDetail {
    if summaries[threadID] == nil { _ = try await refreshWorkspace() }
    guard var summary = summaries[threadID] else {
      throw AppServerFailure(message: "Thread \(threadID) was not found")
    }

    let response = try await connection.request(
      method: "thread/turns/list",
      params: [
        "threadId": .string(threadID),
        "limit": 60,
        "sortDirection": "desc",
        "itemsView": "full",
      ]
    )
    let newestFirst = response["data"]?.arrayValue ?? []
    let mapped = CodexTimelineMapper.mapTurns(Array(newestFirst.reversed()), threadID: threadID)
    if let activeTurnID = mapped.activeTurnID {
      activeTurnIDs[threadID] = activeTurnID
      summary = Self.copy(
        summary,
        status: .active,
        controlLevel: controlLevel(for: threadID),
        activeTurnID: activeTurnID
      )
      summaries[threadID] = summary
    } else {
      activeTurnIDs.removeValue(forKey: threadID)
    }

    return ThreadDetail(
      thread: summary,
      timeline: mapped.items,
      pendingActions: pendingRequests.values
        .map(\.action)
        .filter { $0.threadID == threadID }
        .sorted { $0.createdAt < $1.createdAt }
    )
  }

  @discardableResult
  public func sendMessage(threadID: String, text: String) async throws -> String? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw AppServerFailure(message: "Message cannot be empty")
    }
    let detail = try await threadDetail(threadID: threadID)

    if let activeTurnID = detail.thread.activeTurnID {
      if controlLevel(for: threadID) == .live {
        _ = try await connection.request(
          method: "turn/steer",
          params: [
            "threadId": .string(threadID),
            "expectedTurnId": .string(activeTurnID),
            "input": [["type": "text", "text": .string(normalized)]],
          ]
        )
        return activeTurnID
      }
      try queueMessage(threadID: threadID, text: normalized)
      return activeTurnID
    }

    if !liveThreadIDs.contains(threadID) {
      _ = try await connection.request(
        method: "thread/resume",
        params: ["threadId": .string(threadID)]
      )
      liveThreadIDs.insert(threadID)
    }

    let response = try await connection.request(
      method: "turn/start",
      params: [
        "threadId": .string(threadID),
        "input": [["type": "text", "text": .string(normalized)]],
      ]
    )
    let turnID = response["turn"]?["id"]?.stringValue
    if let turnID { activeTurnIDs[threadID] = turnID }
    return turnID
  }

  public func interrupt(threadID: String, turnID: String) async throws {
    guard controlLevel(for: threadID) == .live else {
      throw AppServerFailure(message: "This CLI thread is not under live bridge control")
    }
    _ = try await connection.request(
      method: "turn/interrupt",
      params: ["threadId": .string(threadID), "turnId": .string(turnID)]
    )
  }

  public func recordServerRequest(
    id: JSONValue,
    method: String,
    params: JSONValue
  ) -> PendingAction? {
    let requestID = id.requestKey
    guard let action = Self.pendingAction(method: method, params: params, requestID: requestID)
    else { return nil }
    pendingRequests[requestID] = PendingServerRequest(
      rpcID: id,
      method: method,
      params: params,
      action: action
    )
    return action
  }

  public func answerApproval(_ response: ApprovalResponse) async throws {
    guard let request = pendingRequests[response.requestID] else {
      throw AppServerFailure(message: "Approval request is no longer pending")
    }
    let result: JSONValue
    if request.method == "item/permissions/requestApproval" {
      switch response.decision {
      case .accept, .acceptForSession:
        result = [
          "permissions": request.params["permissions"] ?? [:],
          "scope": response.decision == .acceptForSession ? "session" : "turn",
        ]
      case .decline, .cancel:
        result = ["permissions": [:], "scope": "turn"]
      }
    } else {
      result = ["decision": .string(response.decision.rawValue)]
    }
    try await connection.respond(id: request.rpcID, result: result)
    pendingRequests.removeValue(forKey: response.requestID)
  }

  public func answerUserInput(_ response: UserInputResponse) async throws {
    guard let request = pendingRequests[response.requestID],
      request.method == "item/tool/requestUserInput"
    else {
      throw AppServerFailure(message: "Input request is no longer pending")
    }
    let answers = response.answers.mapValues { value in
      JSONValue.object(["answers": .array([.string(value)])])
    }
    try await connection.respond(
      id: request.rpcID,
      result: .object(["answers": .object(answers)])
    )
    pendingRequests.removeValue(forKey: response.requestID)
  }

  public func isSubscribed(threadID: String) -> Bool {
    subscribedThreadIDs.contains(threadID)
  }

  private func controlLevel(for threadID: String) -> ThreadControlLevel {
    if liveThreadIDs.contains(threadID) || rawThreads[threadID]?.directlyControllable == true {
      return .live
    }
    return .message
  }

  static func directControlAvailable(
    statusType: String?,
    canAcceptDirectInput: Bool
  ) -> Bool {
    canAcceptDirectInput || statusType == "active" || statusType == "idle"
  }

  private func queueMessage(threadID: String, text: String) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["codex", "queue", "--thread", threadID, "--message", text]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let data = output.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "codex queue failed"
      throw AppServerFailure(code: Int(process.terminationStatus), message: message)
    }
  }

  private static func runtimeStatus(
    _ value: JSONValue?,
    activeFlags: [String]
  ) -> ThreadRuntimeStatus {
    switch value?["type"]?.stringValue {
    case "active":
      return activeFlags.contains("waitingOnApproval")
        || activeFlags.contains("waitingOnUserInput")
        ? .waiting : .active
    case "idle": return .idle
    case "systemError": return .systemError
    default: return .notLoaded
    }
  }

  private static func pendingAction(
    method: String,
    params: JSONValue,
    requestID: String
  ) -> PendingAction? {
    guard let threadID = params["threadId"]?.stringValue else { return nil }
    switch method {
    case "item/commandExecution/requestApproval":
      let command = params["command"]?.stringValue ?? "Command"
      return PendingAction(
        id: requestID,
        threadID: threadID,
        kind: .commandApproval,
        title: "Run command?",
        detail: [command, params["reason"]?.stringValue].compactMap { $0 }.joined(
          separator: "\n\n"),
        options: approvalOptions
      )
    case "item/fileChange/requestApproval":
      return PendingAction(
        id: requestID,
        threadID: threadID,
        kind: .fileApproval,
        title: "Apply file changes?",
        detail: params["reason"]?.stringValue ?? "Codex wants to edit files in this project.",
        options: approvalOptions
      )
    case "item/permissions/requestApproval":
      return PendingAction(
        id: requestID,
        threadID: threadID,
        kind: .permissions,
        title: "Grant access?",
        detail: params["reason"]?.stringValue ?? params["permissions"]?.compactDescription() ?? "",
        options: approvalOptions
      )
    case "item/tool/requestUserInput":
      let questions = params["questions"]?.arrayValue ?? []
      let title = questions.first?["header"]?.stringValue ?? "Codex needs input"
      let detail = questions.compactMap { $0["question"]?.stringValue }.joined(separator: "\n\n")
      let pendingQuestions: [PendingQuestion] = questions.compactMap { question in
        guard let questionID = question["id"]?.stringValue,
          let prompt = question["question"]?.stringValue
        else { return nil }
        let options: [PendingActionOption] = (question["options"]?.arrayValue ?? []).compactMap {
          option in
          guard let label = option["label"]?.stringValue else { return nil }
          return PendingActionOption(
            id: label,
            label: label,
            detail: option["description"]?.stringValue
          )
        }
        return PendingQuestion(id: questionID, prompt: prompt, options: options)
      }
      return PendingAction(
        id: requestID,
        threadID: threadID,
        kind: .userInput,
        title: title,
        detail: detail,
        options: [],
        questions: pendingQuestions
      )
    default:
      return nil
    }
  }

  private static var approvalOptions: [PendingActionOption] {
    [
      PendingActionOption(id: ApprovalDecision.accept.rawValue, label: "Allow once"),
      PendingActionOption(
        id: ApprovalDecision.acceptForSession.rawValue, label: "Allow for session"),
      PendingActionOption(id: ApprovalDecision.decline.rawValue, label: "Decline"),
    ]
  }

  private static func copy(
    _ value: ThreadSummary,
    status: ThreadRuntimeStatus,
    controlLevel: ThreadControlLevel,
    activeTurnID: String?
  ) -> ThreadSummary {
    ThreadSummary(
      id: value.id,
      title: value.title,
      preview: value.preview,
      cwd: value.cwd,
      repositoryRoot: value.repositoryRoot,
      source: value.source,
      status: status,
      controlLevel: controlLevel,
      activeTurnID: activeTurnID,
      needsAttention: value.needsAttention,
      updatedAt: value.updatedAt
    )
  }
}
