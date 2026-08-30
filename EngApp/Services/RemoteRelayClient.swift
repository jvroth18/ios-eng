import CryptoKit
import EngCore
import Foundation

final class RemoteRelayClient: @unchecked Sendable {
  private let deviceID: UUID
  private let deviceName: String
  private let pairingKey: Curve25519.KeyAgreement.PrivateKey
  private let lock = NSLock()
  private var peer: RelayHTTPPeer?
  private var bootstrap: TransportBootstrap?
  private var eventHandler: (@Sendable (BridgeClientEvent) -> Void)?
  private var retryTask: Task<Void, Never>?
  private var wantsConnection = false
  private(set) var configuration: RemoteRelayConfiguration?

  let kind = BridgeTransportKind.remoteRelay

  init(deviceID: UUID, deviceName: String) {
    self.deviceID = deviceID
    self.deviceName = deviceName
    pairingKey = DeviceIdentityKey.loadOrCreate()
  }

  var identityPublicKey: Data? { pairingKey.publicKey.rawRepresentation }
  var connected: Bool { lock.withLock { bootstrap?.isValid() == true } }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { eventHandler = handler }
  }

  func configure(_ configuration: RemoteRelayConfiguration?) {
    stop()
    self.configuration = configuration
    if configuration != nil { start() }
  }

  func start() {
    guard let configuration else { return }
    let shouldStart = lock.withLock { () -> Bool in
      wantsConnection = true
      return peer == nil
    }
    guard shouldStart else { return }
    emit(.state(.connecting("Mac · Remote")))
    let relayPeer = RelayHTTPPeer(configuration: configuration, role: .phone)
    lock.withLock { self.peer = relayPeer }
    relayPeer.start { [weak self] result in
      switch result {
      case .success(let data): self?.receive(data)
      case .failure(let error): self?.handleFailure(error)
      }
    }
    retryTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.sendHello()
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  func stop() {
    let values = lock.withLock { () -> (RelayHTTPPeer?, Task<Void, Never>?) in
      wantsConnection = false
      let values = (peer, retryTask)
      peer = nil
      retryTask = nil
      bootstrap = nil
      return values
    }
    values.0?.stop()
    values.1?.cancel()
  }

  func send(_ envelope: BridgeEnvelope) throws {
    guard let peer = lock.withLock({ self.peer }),
      let bootstrap = lock.withLock({ self.bootstrap }), bootstrap.isValid()
    else {
      throw BridgeError(
        code: "relay_disconnected", message: "The remote connection is not ready.",
        recoverable: true)
    }
    let packet = try SecureTransportCodec.seal(envelope, using: bootstrap)
    Task { try await peer.send(packet) }
  }

  private func sendHello() async {
    guard !connected, let peer = lock.withLock({ self.peer }) else { return }
    do {
      let hello = DirectPairingHello(
        deviceID: deviceID, deviceName: deviceName,
        clientPublicKey: pairingKey.publicKey.rawRepresentation)
      try await peer.send(JSONEncoder().encode(hello))
    } catch { emit(.state(.failed("Remote: \(error.localizedDescription)"))) }
  }

  private func receive(_ data: Data) {
    do {
      if !connected {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(DirectPairingResponse.self, from: data)
        guard DeviceIdentityKey.acceptsServerPublicKey(response.serverPublicKey) else {
          throw BridgeError(
            code: "relay_identity", message: "The Mac identity changed. Remote connection refused.",
            recoverable: false)
        }
        let credential = try DirectPairingKeyAgreement.bootstrap(
          deviceID: deviceID, privateKey: pairingKey,
          remotePublicKey: response.serverPublicKey,
          issuedAt: response.issuedAt, expiresAt: response.expiresAt)
        lock.withLock { bootstrap = credential }
        emit(.state(.connected("Mac · Remote")))
        return
      }
      guard let bootstrap = lock.withLock({ self.bootstrap }) else { return }
      emit(.envelope(try SecureTransportCodec.open(data, using: bootstrap)))
    } catch { emit(.state(.failed("Remote: \(error.localizedDescription)"))) }
  }

  private func handleFailure(_ error: Error) {
    lock.withLock { bootstrap = nil }
    emit(.state(.failed("Remote: \(error.localizedDescription)")))
  }

  private func emit(_ event: BridgeClientEvent) { lock.withLock { eventHandler }?(event) }
}
