import Foundation
import Testing

@testable import EngBridgeCore

struct BridgeRuntimeStateTests {
  @Test func publishesLoadsAndClearsOwnedRuntime() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "eng-runtime-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = BridgeRuntimeState(fileURL: root.appending(path: "runtime.json"))
    let record = BridgeRuntimeRecord(
      port: 47_329,
      bridgePID: 12_345,
      startedAt: Date(timeIntervalSince1970: 1_787_895_600)
    )

    try state.publish(record)

    #expect(try state.load() == record)
    let attributes = try FileManager.default.attributesOfItem(atPath: state.fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    state.clear(ifOwnedBy: 54_321)
    #expect(FileManager.default.fileExists(atPath: state.fileURL.path))

    state.clear(ifOwnedBy: record.bridgePID)
    #expect(!FileManager.default.fileExists(atPath: state.fileURL.path))
  }
}
