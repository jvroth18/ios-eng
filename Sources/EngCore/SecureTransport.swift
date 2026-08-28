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

public struct DirectPairingHello: Codable, Equatable, Sendable {
  public let deviceID: UUID
  public let deviceName: String
  public let protocolVersion: Int
  public let clientPublicKey: Data

  public init(
    deviceID: UUID,
    deviceName: String,
    protocolVersion: Int = BridgeEnvelope.currentProtocolVersion,
    clientPublicKey: Data
  ) {
    self.deviceID = deviceID
    self.deviceName = deviceName
    self.protocolVersion = protocolVersion
    self.clientPublicKey = clientPublicKey
  }
}

public struct DirectPairingResponse: Codable, Equatable, Sendable {
  public let serverPublicKey: Data
  public let issuedAt: Date
  public let expiresAt: Date

  public init(serverPublicKey: Data, issuedAt: Date, expiresAt: Date) {
    self.serverPublicKey = serverPublicKey
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
  }
}

public enum DirectPairingKeyAgreement {
  public static func bootstrap(
    deviceID: UUID,
    privateKey: Curve25519.KeyAgreement.PrivateKey,
    remotePublicKey: Data,
    issuedAt: Date,
    expiresAt: Date
  ) throws -> TransportBootstrap {
    let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remotePublicKey)
    let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: Data("ios-eng-direct-v1".utf8),
      sharedInfo: Data(deviceID.uuidString.lowercased().utf8),
      outputByteCount: TransportBootstrap.secretByteCount
    )
    let secret = symmetricKey.withUnsafeBytes { Data($0) }
    return try TransportBootstrap(
      deviceID: deviceID,
      secret: secret,
      issuedAt: issuedAt,
      expiresAt: expiresAt
    )
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

public final class SecureTransportRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var credentials: [UUID: TransportBootstrap] = [:]

  public init() {}

  public func credential(for deviceID: UUID) -> TransportBootstrap? {
    lock.withLock {
      guard let credential = credentials[deviceID], credential.isValid() else {
        credentials.removeValue(forKey: deviceID)
        return nil
      }
      return credential
    }
  }

  @discardableResult
  public func issue(for deviceID: UUID) throws -> TransportBootstrap {
    if let credential = credential(for: deviceID) { return credential }
    let credential = try TransportBootstrap.generate(deviceID: deviceID)
    lock.withLock { credentials[deviceID] = credential }
    return credential
  }

  public func install(_ credential: TransportBootstrap) {
    guard credential.isValid() else { return }
    lock.withLock { credentials[credential.deviceID] = credential }
  }
}

public struct NewlineFrameBuffer: Sendable {
  private var buffered = Data()

  public init() {}

  public mutating func append(_ data: Data) throws -> [Data] {
    buffered.append(data)
    guard buffered.count <= SecureTransportCodec.maximumPacketBytes + 1 else {
      throw SecureTransportError.frameTooLarge
    }
    var frames: [Data] = []
    while let newline = buffered.firstIndex(of: 0x0A) {
      let frame = Data(buffered[..<newline])
      buffered.removeSubrange(...newline)
      guard !frame.isEmpty else { continue }
      guard frame.count <= SecureTransportCodec.maximumPacketBytes else {
        throw SecureTransportError.frameTooLarge
      }
      frames.append(frame)
    }
    return frames
  }

  public static func encode(_ frame: Data) throws -> Data {
    guard frame.count <= SecureTransportCodec.maximumPacketBytes else {
      throw SecureTransportError.frameTooLarge
    }
    var encoded = frame
    encoded.append(0x0A)
    return encoded
  }
}
