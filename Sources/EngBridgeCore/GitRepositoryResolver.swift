import Foundation

public actor GitRepositoryResolver {
  private var rootCache: [String: String] = [:]

  public init() {}

  public func repositoryRoot(for cwd: String) -> String {
    if let cached = rootCache[cwd] { return cached }
    let resolved = runGit(cwd: cwd, arguments: ["rev-parse", "--show-toplevel"]) ?? cwd
    rootCache[cwd] = resolved
    return resolved
  }

  private func runGit(cwd: String, arguments: [String]) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", cwd] + arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      let data = output.fileHandleForReading.readDataToEndOfFile()
      return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }
}
