import Darwin
import Foundation

enum OwnedProcessTree {
  static func terminate(_ root: Process) async {
    let processIDs = descendants(of: root.processIdentifier) + [root.processIdentifier]
    for processID in processIDs.reversed() where isAlive(processID) {
      _ = Darwin.kill(processID, SIGTERM)
    }
    for _ in 0..<20 {
      guard processIDs.contains(where: isAlive) else { return }
      try? await Task.sleep(for: .milliseconds(50))
    }
    for processID in processIDs.reversed() where isAlive(processID) {
      _ = Darwin.kill(processID, SIGKILL)
    }
  }

  static func descendants(of rootProcessID: Int32) -> [Int32] {
    var result: [Int32] = []
    var pending = [rootProcessID]
    while let parent = pending.first {
      pending.removeFirst()
      let children = childProcessIDs(of: parent).filter { !result.contains($0) }
      result.append(contentsOf: children)
      pending.append(contentsOf: children)
    }
    return result
  }

  static func isAlive(_ processID: Int32) -> Bool {
    if Darwin.kill(processID, 0) == 0 { return true }
    return errno == EPERM
  }

  private static func childProcessIDs(of parent: Int32) -> [Int32] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-P", String(parent)]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(whereSeparator: \Character.isNewline)
        .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    } catch {
      return []
    }
  }
}
