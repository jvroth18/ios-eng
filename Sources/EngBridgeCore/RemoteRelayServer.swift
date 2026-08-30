import CryptoKit
import EngCore
import Foundation

public final class RemoteRelayServer: @unchecked Sendable {
  private let registry: SecureTransportRegistry
  private let pairingKey: Curve25519.KeyAgreement.PrivateKey
  private let identityValidator: @Sendable (UUID, Data) -> Bool
  private let peer: RelayHTTPPeer
  private let lock = NSLock()
  private var connectedDeviceID: UUID?
  private var envelopeHandler: (@Sendable (String, BridgeEnvelope) -> Void)?
  private var stateHandler: (@Sendable (String, BridgeTransportPeerState) -> Void)?

  public let kind = BridgeTransportKind.remoteRelay

  public init(
    configuration: RemoteRelayConfiguration,
    registry: SecureTransportRegistry,
    pairingKey: Curve25519.KeyAgreement.PrivateKey,
    identityValidator: @escaping @Sendable (UUID, Data) -> Bool
  ) {
    self.registry = registry
    self.pairingKey = pairingKey
    self.identityValidator = identityValidator
    peer = RelayHTTPPeer(configuration: configuration, role: .bridge)
  }

  public func setHandlers(
    envelope: @escaping @Sendable (String, BridgeEnvelope) -> Void,
    state: @escaping @Sendable (String, BridgeTransportPeerState) -> Void
  ) {
    lock.withLock { envelopeHandler = envelope; stateHandler = state }
  }

  public func start() {
    peer.start { [weak self] result in
      switch result {
      case .success(let data): self?.receive(data)
      case .failure: self?.disconnect()
      }
    }
  }

  public func stop() { peer.stop(); disconnect() }

  public var connectedPeerNames: [String] {
    lock.withLock { connectedDeviceID.map { ["relay:\($0.uuidString)"] } ?? [] }
  }

  public func send(_ envelope: BridgeEnvelope, to peerName: String) throws {
    guard let deviceID = Self.deviceID(from: peerName),
      connectedPeerNames.contains(peerName),
      let bootstrap = registry.credential(for: deviceID)
    else { throw BridgeError(code: "relay_disconnected", message: "The remote relay link is unavailable.", recoverable: true) }
    let packet = try SecureTransportCodec.seal(envelope, using: bootstrap)
    Task { try? await peer.send(packet) }
  }

  private func receive(_ data: Data) {
    do {
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      if let hello = try? decoder.decode(DirectPairingHello.self, from: data) {
        guard hello.protocolVersion == BridgeEnvelope.currentProtocolVersion,
          identityValidator(hello.deviceID, hello.clientPublicKey)
        else { throw SecureTransportError.invalidCredential }
        let now = Date(), expires = now.addingTimeInterval(12 * 60 * 60)
        registry.install(try DirectPairingKeyAgreement.bootstrap(
          deviceID: hello.deviceID, privateKey: pairingKey,
          remotePublicKey: hello.clientPublicKey, issuedAt: now, expiresAt: expires))
        let response = DirectPairingResponse(
          serverPublicKey: pairingKey.publicKey.rawRepresentation, issuedAt: now, expiresAt: expires)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        Task { try? await peer.send(encoder.encode(response)) }
        lock.withLock { connectedDeviceID = hello.deviceID }
        lock.withLock { stateHandler }?("relay:\(hello.deviceID.uuidString)", .connected)
        return
      }
      let packet = try decoder.decode(SecureTransportPacket.self, from: data)
      guard let bootstrap = registry.credential(for: packet.deviceID) else { throw SecureTransportError.invalidCredential }
      let envelope = try SecureTransportCodec.open(data, using: bootstrap)
      lock.withLock { envelopeHandler }?("relay:\(packet.deviceID.uuidString)", envelope)
    } catch { disconnect() }
  }

  private func disconnect() {
    let deviceID = lock.withLock { () -> UUID? in defer { connectedDeviceID = nil }; return connectedDeviceID }
    if let deviceID { lock.withLock { stateHandler }?("relay:\(deviceID.uuidString)", .disconnected) }
  }

  private static func deviceID(from name: String) -> UUID? {
    guard name.hasPrefix("relay:") else { return nil }
    return UUID(uuidString: String(name.dropFirst(6)))
  }
}

extension RemoteRelayServer: BridgeServerTransport {}
