import Darwin
import Foundation

public protocol ExternalThreadControlling: Sendable {
  func queue(threadID: String, message: String) async throws
  func interrupt(threadID: String) async throws
}

public struct ExternalThreadControlFailure: Error, LocalizedError, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String? { message }
}

struct ShellResult: Sendable {
  let status: Int32
  let output: String
  let error: String
}

public struct CodexCLIExternalThreadController: ExternalThreadControlling {
  typealias Runner = @Sendable (String, [String]) async throws -> ShellResult
  typealias SignalSender = @Sendable (Int32, Int32) throws -> Void

  private let run: Runner
  private let sendSignal: SignalSender
  private let userID: UInt32
  private let codexHome: URL

  public init() {
    run = Self.runProcess
    sendSignal = Self.signal
    userID = getuid()
    codexHome = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
  }

  init(
    codexHome: URL,
    userID: UInt32,
    run: @escaping Runner,
    sendSignal: @escaping SignalSender
  ) {
    self.codexHome = codexHome
    self.userID = userID
    self.run = run
    self.sendSignal = sendSignal
  }

  public func queue(threadID: String, message: String) async throws {
    try validate(threadID: threadID)
    let result = try await run(
      "/usr/bin/env",
      ["codex", "queue", "--thread", threadID, "--message", message]
    )
    guard result.status == 0 else {
      throw ExternalThreadControlFailure(
        result.error.nonempty ?? result.output.nonempty
          ?? "Codex could not queue the message for the Mac-owned thread."
      )
    }
  }

  public func interrupt(threadID: String) async throws {
    try validate(threadID: threadID)
    let lockURL =
      codexHome
      .appending(path: "thread-writer-locks", directoryHint: .isDirectory)
      .appending(path: "\(threadID).lock", directoryHint: .notDirectory)
    let owners = try await run("/usr/sbin/lsof", ["-t", lockURL.path])
    let processIDs = Set(
      owners.output.split(whereSeparator: \Character.isNewline).compactMap {
        Int32($0.trimmingCharacters(in: .whitespacesAndNewlines))
      })
    guard owners.status == 0, processIDs.count == 1, let processID = processIDs.first else {
      throw ExternalThreadControlFailure(
        "The Mac writer could not be identified safely. Stop this turn from Codex on the Mac."
      )
    }

    let process = try await run(
      "/bin/ps", ["-o", "uid=", "-o", "tty=", "-o", "comm=", "-p", String(processID)])
    guard process.status == 0,
      Self.isSafeInteractiveCodexWriter(process.output, expectedUserID: userID)
    else {
      throw ExternalThreadControlFailure(
        "This Mac writer is not an interactive Codex CLI. Stop this turn from its Mac window."
      )
    }
    try sendSignal(processID, SIGINT)
  }

  static func isSafeInteractiveCodexWriter(
    _ processDescription: String,
    expectedUserID: UInt32
  ) -> Bool {
    let fields = processDescription.split(
      maxSplits: 2,
      omittingEmptySubsequences: true,
      whereSeparator: \Character.isWhitespace
    )
    guard fields.count == 3,
      UInt32(fields[0]) == expectedUserID,
      fields[1] != "??"
    else { return false }
    return URL(fileURLWithPath: String(fields[2])).lastPathComponent == "codex"
  }

  private func validate(threadID: String) throws {
    guard UUID(uuidString: threadID) != nil else {
      throw ExternalThreadControlFailure("The selected Codex thread identifier is invalid.")
    }
  }

  private static func runProcess(
    executable: String,
    arguments: [String]
  ) async throws -> ShellResult {
    try await Task.detached {
      let process = Process()
      let output = Pipe()
      let error = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = output
      process.standardError = error
      try process.run()
      process.waitUntilExit()
      return ShellResult(
        status: process.terminationStatus,
        output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        error: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      )
    }.value
  }

  private static func signal(processID: Int32, signal: Int32) throws {
    guard kill(processID, signal) == 0 else {
      throw ExternalThreadControlFailure(
        "Codex could not stop the Mac turn: \(String(cString: strerror(errno)))."
      )
    }
  }
}

extension String {
  fileprivate var nonempty: String? {
    let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}
