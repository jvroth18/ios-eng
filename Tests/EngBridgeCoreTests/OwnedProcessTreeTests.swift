import Foundation
import Testing

@testable import EngBridgeCore

struct OwnedProcessTreeTests {
  @Test func terminatesTheOwnedWrapperAndItsSpawnedChild() async throws {
    let root = Process()
    root.executableURL = URL(fileURLWithPath: "/bin/sh")
    root.arguments = ["-c", "/bin/sleep 30 & wait"]
    root.standardOutput = FileHandle.nullDevice
    root.standardError = FileHandle.nullDevice
    try root.run()

    var descendants: [Int32] = []
    for _ in 0..<20 where descendants.isEmpty {
      descendants = OwnedProcessTree.descendants(of: root.processIdentifier)
      if descendants.isEmpty { try await Task.sleep(for: .milliseconds(25)) }
    }
    #expect(!descendants.isEmpty)

    await OwnedProcessTree.terminate(root)

    #expect(!OwnedProcessTree.isAlive(root.processIdentifier))
    #expect(descendants.allSatisfy { !OwnedProcessTree.isAlive($0) })
  }
}
