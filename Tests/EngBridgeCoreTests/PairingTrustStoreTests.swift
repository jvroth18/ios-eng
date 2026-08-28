import EngBridgeCore
import Foundation
import Testing

struct PairingTrustStoreTests {
  @Test func persistsTrustedDeviceIDsAcrossStoreInstances() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "trusted-devices.json")
    let first = UUID()
    let second = UUID()

    let writer = PairingTrustStore(fileURL: file)
    try writer.trust(first)
    try writer.trust(first)
    try writer.trust(second)

    let reader = PairingTrustStore(fileURL: file)
    #expect(reader.trustedDeviceIDs() == [first, second])
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }
}
