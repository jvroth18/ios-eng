import CryptoKit
import Foundation

public final class PairingTrustStore: @unchecked Sendable {
  private struct Document: Codable {
    var deviceIDs: Set<UUID>
    var identityPublicKeys: [String: Data]? = nil
    var serverPrivateKey: Data? = nil
  }

  private let fileURL: URL
  private let lock = NSLock()

  public init(fileURL: URL = PairingTrustStore.defaultFileURL()) {
    self.fileURL = fileURL
  }

  public func trustedDeviceIDs() -> Set<UUID> {
    lock.withLock {
      guard let data = try? Data(contentsOf: fileURL),
        let document = try? JSONDecoder().decode(Document.self, from: data)
      else { return [] }
      return document.deviceIDs
    }
  }

  public func matchesIdentity(deviceID: UUID, publicKey: Data) -> Bool {
    lock.withLock {
      guard let document = load(),
        let trusted = document.identityPublicKeys?[deviceID.uuidString]
      else { return true }
      return trusted == publicKey
    }
  }

  public func trust(_ deviceID: UUID, identityPublicKey: Data? = nil) throws {
    try lock.withLock {
      var document = load() ?? Document(deviceIDs: [])
      let inserted = document.deviceIDs.insert(deviceID).inserted
      var addedIdentity = false
      if let identityPublicKey,
        document.identityPublicKeys?[deviceID.uuidString] == nil
      {
        if document.identityPublicKeys == nil { document.identityPublicKeys = [:] }
        document.identityPublicKeys?[deviceID.uuidString] = identityPublicKey
        addedIdentity = true
      }
      guard inserted || addedIdentity else { return }
      try write(document)
    }
  }

  public func directPairingPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
    try lock.withLock {
      var document = load() ?? Document(deviceIDs: [])
      if let data = document.serverPrivateKey,
        let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
      {
        return key
      }
      let key = Curve25519.KeyAgreement.PrivateKey()
      document.serverPrivateKey = key.rawRepresentation
      try write(document)
      return key
    }
  }

  private func load() -> Document? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(Document.self, from: data)
  }

  private func write(_ document: Document) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(document).write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  public static func defaultFileURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "Eng", directoryHint: .isDirectory)
      .appending(path: "trusted-devices.json", directoryHint: .notDirectory)
  }
}
