import CryptoKit
import Foundation

public struct TransportBootstrap: Codable, Equatable, Sendable {
  public static let secretByteCount = 32

  public let deviceID: UUID
  public let secret: Data
  public let issuedAt: Date
  public let expiresAt: Date

  public init(
    deviceID: UUID,
    secret: Data,
    issuedAt: Date = Date(),
    expiresAt: Date
  ) throws {
    guard secret.count == Self.secretByteCount else {
      throw SecureTransportError.invalidCredential
    }
    self.deviceID = deviceID
    self.secret = secret
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
  }

  public static func generate(
    deviceID: UUID,
    validFor lifetime: TimeInterval = 12 * 60 * 60,
    now: Date = Date()
  ) throws -> TransportBootstrap {
    var generator = SystemRandomNumberGenerator()
    let secret = Data(
      (0..<secretByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    return try TransportBootstrap(
      deviceID: deviceID,
      secret: secret,
      issuedAt: now,
      expiresAt: now.addingTimeInterval(lifetime)
    )
  }

  public func isValid(at date: Date = Date()) -> Bool {
    secret.count == Self.secretByteCount && date >= issuedAt && date < expiresAt
  }
}

public struct SecureTransportPacket: Codable, Equatable, Sendable {
  public let deviceID: UUID
  public let sealedEnvelope: Data

  public init(deviceID: UUID, sealedEnvelope: Data) {
    self.deviceID = deviceID
    self.sealedEnvelope = sealedEnvelope
  }
}

public enum SecureTransportError: Error, Equatable, LocalizedError, Sendable {
  case invalidCredential
  case expiredCredential
  case invalidPacket
  case frameTooLarge

  public var errorDescription: String? {
    switch self {
    case .invalidCredential: "The secure transport credential is invalid."
    case .expiredCredential: "The secure transport credential expired. Reconnect nearby."
    case .invalidPacket: "The secure transport packet could not be authenticated."
    case .frameTooLarge: "The secure transport frame exceeds the safety limit."
    }
  }
}

public enum SecureTransportCodec {
  public static let maximumPacketBytes = 2 * 1_024 * 1_024

  public static func seal(
    _ envelope: BridgeEnvelope,
    using bootstrap: TransportBootstrap,
    now: Date = Date()
  ) throws -> Data {
    guard bootstrap.isValid(at: now) else { throw SecureTransportError.expiredCredential }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let plaintext = try encoder.encode(envelope)
    let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: bootstrap.secret))
    guard let combined = sealed.combined else { throw SecureTransportError.invalidPacket }
    let packet = SecureTransportPacket(deviceID: bootstrap.deviceID, sealedEnvelope: combined)
    let data = try encoder.encode(packet)
    guard data.count <= maximumPacketBytes else { throw SecureTransportError.frameTooLarge }
    return data
  }

  public static func open(
    _ data: Data,
    using bootstrap: TransportBootstrap,
    now: Date = Date()
  ) throws -> BridgeEnvelope {
    guard data.count <= maximumPacketBytes else { throw SecureTransportError.frameTooLarge }
    guard bootstrap.isValid(at: now) else { throw SecureTransportError.expiredCredential }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let packet = try decoder.decode(SecureTransportPacket.self, from: data)
    guard packet.deviceID == bootstrap.deviceID else { throw SecureTransportError.invalidPacket }
    do {
      let box = try AES.GCM.SealedBox(combined: packet.sealedEnvelope)
      let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: bootstrap.secret))
      return try decoder.decode(BridgeEnvelope.self, from: plaintext)
    } catch {
      throw SecureTransportError.invalidPacket
    }
  }
}
