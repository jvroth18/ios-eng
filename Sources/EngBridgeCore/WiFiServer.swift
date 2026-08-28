import CryptoKit
import EngCore
import Foundation
@preconcurrency import Network

public final class WiFiServer: @unchecked Sendable {
  public static let serviceName = "ios-eng-fast"

  private let registry: SecureTransportRegistry
  private let pairingKey: Curve25519.KeyAgreement.PrivateKey
  private let identityValidator: @Sendable (UUID, Data) -> Bool
  private let queue = DispatchQueue(label: "dev.jvroth.eng.wifi-server")
  private let lock = NSLock()
  private var listener: NWListener?
  private var connections: [String: NWConnection] = [:]
  private var envelopeHandler: (@Sendable (String, BridgeEnvelope) -> Void)?
  private var stateHandler: (@Sendable (String, BridgeTransportPeerState) -> Void)?

  public let kind = BridgeTransportKind.wifiDirect

  public init(
    registry: SecureTransportRegistry,
    pairingKey: Curve25519.KeyAgreement.PrivateKey = Curve25519.KeyAgreement.PrivateKey(),
    identityValidator: @escaping @Sendable (UUID, Data) -> Bool = { _, _ in true }
  ) {
    self.registry = registry
    self.pairingKey = pairingKey
    self.identityValidator = identityValidator
  }

  public func setHandlers(
    envelope: @escaping @Sendable (String, BridgeEnvelope) -> Void,
    state: @escaping @Sendable (String, BridgeTransportPeerState) -> Void
  ) {
    lock.withLock {
      envelopeHandler = envelope
      stateHandler = state
    }
  }

  public func start() {
    do {
      let parameters = NWParameters.tcp
      parameters.includePeerToPeer = true
      let listener = try NWListener(using: parameters)
      listener.service = NWListener.Service(
        name: Host.current().localizedName, type: "_\(Self.serviceName)._tcp")
      listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
      listener.stateUpdateHandler = { state in
        if case .failed(let error) = state {
          FileHandle.standardError.write(Data("Eng direct listener failed: \(error)\n".utf8))
        }
      }
      lock.withLock { self.listener = listener }
      listener.start(queue: queue)
    } catch {
      FileHandle.standardError.write(
        Data("Eng direct listener failed: \(error.localizedDescription)\n".utf8))
    }
  }

  public func stop() {
    let values = lock.withLock { () -> (NWListener?, [NWConnection]) in
      let value = (listener, Array(connections.values))
      listener = nil
      connections.removeAll()
      return value
    }
    values.0?.cancel()
    for connection in values.1 { connection.cancel() }
  }

  public var connectedPeerNames: [String] { lock.withLock { Array(connections.keys) } }

  public func send(_ envelope: BridgeEnvelope, to peerName: String) throws {
    guard let deviceID = Self.deviceID(from: peerName),
      let bootstrap = registry.credential(for: deviceID),
      let connection = lock.withLock({ connections[peerName] })
    else {
      throw BridgeError(
        code: "direct_disconnected", message: "The secure direct link is unavailable.",
        recoverable: true)
    }
    let packet = try SecureTransportCodec.seal(envelope, using: bootstrap)
    let frame = try NewlineFrameBuffer.encode(packet)
    connection.send(content: frame, completion: .contentProcessed { _ in })
  }

  private func accept(_ connection: NWConnection) {
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      if case .failed = state { self.remove(connection) }
      if case .cancelled = state { self.remove(connection) }
    }
    connection.start(queue: queue)
    receive(on: connection, buffer: NewlineFrameBuffer(), peerName: nil)
  }

  private func receive(on connection: NWConnection, buffer: NewlineFrameBuffer, peerName: String?) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
      [weak self, weak connection] data, _, complete, error in
      guard let self, let connection else { return }
      var nextBuffer = buffer
      var resolvedPeer = peerName
      do {
        for packetData in try nextBuffer.append(data ?? Data()) {
          if resolvedPeer == nil {
            let hello = try JSONDecoder.eng.decode(DirectPairingHello.self, from: packetData)
            guard hello.protocolVersion == BridgeEnvelope.currentProtocolVersion else {
              throw SecureTransportError.invalidPacket
            }
            guard identityValidator(hello.deviceID, hello.clientPublicKey) else {
              throw SecureTransportError.invalidCredential
            }
            let now = Date()
            let expiresAt = now.addingTimeInterval(12 * 60 * 60)
            let bootstrap = try DirectPairingKeyAgreement.bootstrap(
              deviceID: hello.deviceID,
              privateKey: pairingKey,
              remotePublicKey: hello.clientPublicKey,
              issuedAt: now,
              expiresAt: expiresAt
            )
            registry.install(bootstrap)
            let response = DirectPairingResponse(
              serverPublicKey: pairingKey.publicKey.rawRepresentation,
              issuedAt: now,
              expiresAt: expiresAt
            )
            let responseData = try JSONEncoder.eng.encode(response)
            connection.send(
              content: try NewlineFrameBuffer.encode(responseData),
              completion: .contentProcessed { error in
                if error != nil { connection.cancel() }
              }
            )
            let name = "wifi:\(hello.deviceID.uuidString)"
            resolvedPeer = name
            lock.withLock { connections[name] = connection }
            lock.withLock { stateHandler }?(name, .connected)
            continue
          }
          let packet = try JSONDecoder.eng.decode(SecureTransportPacket.self, from: packetData)
          guard let bootstrap = self.registry.credential(for: packet.deviceID) else {
            throw SecureTransportError.invalidCredential
          }
          let envelope = try SecureTransportCodec.open(packetData, using: bootstrap)
          let name = "wifi:\(packet.deviceID.uuidString)"
          if resolvedPeer == nil {
            resolvedPeer = name
            self.lock.withLock { self.connections[name] = connection }
            self.lock.withLock { self.stateHandler }?(name, .connected)
          }
          self.lock.withLock { self.envelopeHandler }?(name, envelope)
        }
      } catch {
        connection.cancel()
        return
      }
      if complete || error != nil {
        self.remove(connection)
        return
      }
      self.receive(on: connection, buffer: nextBuffer, peerName: resolvedPeer)
    }
  }

  private func remove(_ connection: NWConnection) {
    let removed = lock.withLock { () -> [String] in
      let names = connections.filter { $0.value === connection }.map(\.key)
      for name in names { connections.removeValue(forKey: name) }
      return names
    }
    let handler = lock.withLock { stateHandler }
    for name in removed { handler?(name, .disconnected) }
  }

  private static func deviceID(from peerName: String) -> UUID? {
    guard peerName.hasPrefix("wifi:") else { return nil }
    return UUID(uuidString: String(peerName.dropFirst(5)))
  }
}

extension WiFiServer: BridgeServerTransport {}

extension JSONDecoder {
  fileprivate static var eng: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

extension JSONEncoder {
  fileprivate static var eng: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
