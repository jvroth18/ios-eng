import CryptoKit
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
    let firstKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    let wrongKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

    let writer = PairingTrustStore(fileURL: file)
    try writer.trust(first, identityPublicKey: firstKey)
    try writer.trust(first, identityPublicKey: firstKey)
    try writer.trust(second)

    let reader = PairingTrustStore(fileURL: file)
    #expect(reader.trustedDeviceIDs() == [first, second])
    #expect(reader.matchesIdentity(deviceID: first, publicKey: firstKey))
    #expect(!reader.matchesIdentity(deviceID: first, publicKey: wrongKey))
    #expect(reader.matchesIdentity(deviceID: second, publicKey: wrongKey))
    let serverKey = try writer.directPairingPrivateKey()
    #expect(try reader.directPairingPrivateKey().rawRepresentation == serverKey.rawRepresentation)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }
}
