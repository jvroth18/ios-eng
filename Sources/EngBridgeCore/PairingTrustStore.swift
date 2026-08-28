import Foundation

public final class PairingTrustStore: @unchecked Sendable {
  private struct Document: Codable {
    var deviceIDs: Set<UUID>
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

  public func trust(_ deviceID: UUID) throws {
    try lock.withLock {
      var deviceIDs: Set<UUID> = []
      if let data = try? Data(contentsOf: fileURL),
        let document = try? JSONDecoder().decode(Document.self, from: data)
      {
        deviceIDs = document.deviceIDs
      }
      guard deviceIDs.insert(deviceID).inserted else { return }

      let directory = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(Document(deviceIDs: deviceIDs)).write(to: fileURL, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
  }

  public static func defaultFileURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "Eng", directoryHint: .isDirectory)
      .appending(path: "trusted-devices.json", directoryHint: .notDirectory)
  }
}
