import CryptoKit
import Foundation

public enum RelayPeerRole: String, Codable, CaseIterable, Sendable {
  case phone
  case bridge

  public var opposite: Self { self == .phone ? .bridge : .phone }
}

public struct RelayChannelCredential: Codable, Equatable, Sendable {
  public static let tokenByteCount = 32

  public let channelID: UUID
  public let token: Data

  public init(channelID: UUID, token: Data) throws {
    guard token.count == Self.tokenByteCount else { throw RelayProtocolError.invalidCredential }
    self.channelID = channelID
    self.token = token
  }

  public static func generate() throws -> Self {
    var generator = SystemRandomNumberGenerator()
    let token = Data((0..<tokenByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    return try Self(channelID: UUID(), token: token)
  }

  public var bearerToken: String { token.base64EncodedString() }

  public var tokenDigest: Data { Data(SHA256.hash(data: token)) }
}

public struct RelayOpaqueFrame: Codable, Equatable, Sendable {
  public let sequence: UInt64
  public let payload: Data

  public init(sequence: UInt64, payload: Data) throws {
    guard !payload.isEmpty, payload.count <= SecureTransportCodec.maximumPacketBytes else {
      throw RelayProtocolError.invalidFrame
    }
    self.sequence = sequence
    self.payload = payload
  }
}

public enum RelayProtocolError: Error, Equatable, LocalizedError, Sendable {
  case invalidCredential
  case invalidFrame
  case unauthorized
  case queueFull

  public var errorDescription: String? {
    switch self {
    case .invalidCredential: "The remote relay credential is invalid."
    case .invalidFrame: "The remote relay frame is invalid or too large."
    case .unauthorized: "The remote relay rejected this channel credential."
    case .queueFull: "The remote relay queue is full. Reconnect and retry."
    }
  }
}
