import Foundation

public struct BridgeRuntimeRecord: Codable, Equatable, Sendable {
  public let port: UInt16
  public let bridgePID: Int32
  public let startedAt: Date

  public init(port: UInt16, bridgePID: Int32, startedAt: Date = Date()) {
    self.port = port
    self.bridgePID = bridgePID
    self.startedAt = startedAt
  }
}

public struct BridgeRuntimeState: Sendable {
  public let fileURL: URL

  public init(fileURL: URL = Self.defaultFileURL()) {
    self.fileURL = fileURL
  }

  public func publish(_ record: BridgeRuntimeRecord) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(record).write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  public func load() throws -> BridgeRuntimeRecord {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      BridgeRuntimeRecord.self,
      from: Data(contentsOf: fileURL)
    )
  }

  public func clear(ifOwnedBy bridgePID: Int32) {
    guard let record = try? load(), record.bridgePID == bridgePID else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  public static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "EngBridge", directoryHint: .isDirectory)
      .appending(path: "runtime.json", directoryHint: .notDirectory)
  }
}
