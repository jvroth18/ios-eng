import CryptoKit
import EngCore
import Foundation
@preconcurrency import Network

enum DirectLinkBearer: Equatable, Sendable {
  case wired
  case wifi
  case other

  var connectionName: String {
    switch self {
    case .wired: "Mac · USB-C / Wired"
    case .wifi: "Mac · Direct Wi-Fi"
    case .other: "Mac · Direct Local"
    }
  }

  static func classify(interfaceType: NWInterface.InterfaceType?) -> Self {
    switch interfaceType {
    case .wiredEthernet: .wired
    case .wifi: .wifi
    default: .other
    }
  }
}

final class WiFiClient: @unchecked Sendable {
  private let queue = DispatchQueue(label: "dev.jvroth.eng.wifi-client")
  private let deviceID: UUID
  private let deviceName: String
  private let pairingKey: Curve25519.KeyAgreement.PrivateKey
  private let lock = NSLock()
  private var browser: NWBrowser?
  private var connection: NWConnection?
  private var bootstrap: TransportBootstrap?
  private var eventHandler: (@Sendable (BridgeClientEvent) -> Void)?
  private var isConnected = false
  private var connectionPreference = ConnectionPreference.automatic
  private var wantsConnection = false

  let kind = BridgeTransportKind.wifiDirect

  init(deviceID: UUID, deviceName: String) {
    self.deviceID = deviceID
    self.deviceName = deviceName
    pairingKey = DeviceIdentityKey.loadOrCreate()
  }

  var identityPublicKey: Data? { pairingKey.publicKey.rawRepresentation }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { eventHandler = handler }
  }

  func install(_ bootstrap: TransportBootstrap) {
    guard bootstrap.isValid() else { return }
    let shouldStart = lock.withLock { () -> Bool in
      self.bootstrap = bootstrap
      return browser == nil && connection == nil
    }
    if shouldStart { start() }
  }

  func start() {
    let shouldStart = lock.withLock { () -> Bool in
      wantsConnection = true
      return connectionPreference != .nearbyOnly && connectionPreference != .remoteOnly
        && self.browser == nil && connection == nil
    }
    guard shouldStart else { return }
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    let browser = NWBrowser(
      for: .bonjour(type: "_ios-eng-fast._tcp", domain: nil), using: parameters)
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self else { return }
      let preference = self.lock.withLock { self.connectionPreference }
      guard let selection = Self.preferredSelection(in: results, preference: preference) else {
        return
      }
      let connectionParameters = NWParameters.tcp
      connectionParameters.includePeerToPeer = true
      connectionParameters.requiredInterface = selection.interface
      self.connect(
        to: selection.result.endpoint,
        parameters: connectionParameters,
        bearer: .classify(interfaceType: selection.interface?.type)
      )
    }
    browser.stateUpdateHandler = { [weak self] state in
      if case .failed(let error) = state { self?.emit(.state(.failed(error.localizedDescription))) }
    }
    lock.withLock { self.browser = browser }
    browser.start(queue: queue)
  }

  func stop() {
    let values = lock.withLock { () -> (NWBrowser?, NWConnection?) in
      let values = (browser, connection)
      browser = nil
      connection = nil
      isConnected = false
      wantsConnection = false
      return values
    }
    values.0?.cancel()
    values.1?.cancel()
  }

  func setConnectionPreference(_ preference: ConnectionPreference) {
    let wasStarted = lock.withLock { () -> Bool in
      guard connectionPreference != preference else { return false }
      connectionPreference = preference
      return wantsConnection
    }
    if wasStarted {
      stop()
      if preference != .nearbyOnly && preference != .remoteOnly { start() }
    }
  }

  func send(_ envelope: BridgeEnvelope) throws {
    guard
      let (connection, bootstrap) = lock.withLock({ () -> (NWConnection, TransportBootstrap)? in
        guard isConnected, let connection, let bootstrap else { return nil }
        return (connection, bootstrap)
      })
    else {
      throw BridgeError(
        code: "direct_disconnected", message: "The direct local link is not connected.",
        recoverable: true)
    }
    let packet = try SecureTransportCodec.seal(envelope, using: bootstrap)
    connection.send(
      content: try NewlineFrameBuffer.encode(packet), completion: .contentProcessed { _ in })
  }

  var connected: Bool { lock.withLock { isConnected } }

  private func connect(
    to endpoint: NWEndpoint,
    parameters: NWParameters,
    bearer: DirectLinkBearer
  ) {
    let shouldConnect = lock.withLock { self.connection == nil }
    guard shouldConnect else { return }
    let connection = NWConnection(to: endpoint, using: parameters)
    lock.withLock { self.connection = connection }
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      switch state {
      case .ready:
        self.sendPairingHello(on: connection, bearer: bearer)
      case .failed(let error):
        self.disconnected(error.localizedDescription, connection: connection)
      case .cancelled: self.disconnected(nil, connection: connection)
      default: break
      }
    }
    connection.start(queue: queue)
  }

  private func sendPairingHello(on connection: NWConnection, bearer: DirectLinkBearer) {
    do {
      let hello = DirectPairingHello(
        deviceID: deviceID,
        deviceName: deviceName,
        clientPublicKey: pairingKey.publicKey.rawRepresentation
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let frame = try NewlineFrameBuffer.encode(encoder.encode(hello))
      connection.send(
        content: frame,
        completion: .contentProcessed { [weak self] error in
          if let error {
            self?.disconnected(error.localizedDescription, connection: connection)
          }
        })
      receivePairingResponse(on: connection, buffer: NewlineFrameBuffer(), bearer: bearer)
    } catch {
      disconnected(error.localizedDescription, connection: connection)
    }
  }

  private func receivePairingResponse(
    on connection: NWConnection,
    buffer: NewlineFrameBuffer,
    bearer: DirectLinkBearer
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
      [weak self, weak connection] data, _, complete, error in
      guard let self, let connection else { return }
      var nextBuffer = buffer
      do {
        let frames = try nextBuffer.append(data ?? Data())
        guard let frame = frames.first else {
          if complete || error != nil {
            self.disconnected(error?.localizedDescription, connection: connection)
          } else {
            self.receivePairingResponse(on: connection, buffer: nextBuffer, bearer: bearer)
          }
          return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(DirectPairingResponse.self, from: frame)
        guard DeviceIdentityKey.acceptsServerPublicKey(response.serverPublicKey) else {
          self.emit(
            .state(
              .failed(
                "The Mac identity changed. Refusing the direct connection to protect your data."
              )))
          connection.cancel()
          return
        }
        let bootstrap = try DirectPairingKeyAgreement.bootstrap(
          deviceID: self.deviceID,
          privateKey: self.pairingKey,
          remotePublicKey: response.serverPublicKey,
          issuedAt: response.issuedAt,
          expiresAt: response.expiresAt
        )
        self.lock.withLock {
          self.bootstrap = bootstrap
          self.isConnected = true
          self.browser?.cancel()
          self.browser = nil
        }
        self.emit(.state(.connected(bearer.connectionName)))
        self.receive(on: connection, buffer: NewlineFrameBuffer())
      } catch {
        connection.cancel()
      }
    }
  }

  private func receive(on connection: NWConnection, buffer: NewlineFrameBuffer) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
      [weak self, weak connection] data, _, complete, error in
      guard let self, let connection else { return }
      var nextBuffer = buffer
      do {
        guard let bootstrap = self.lock.withLock({ self.bootstrap }) else { return }
        for packet in try nextBuffer.append(data ?? Data()) {
          self.emit(.envelope(try SecureTransportCodec.open(packet, using: bootstrap)))
        }
      } catch {
        connection.cancel()
        return
      }
      if complete || error != nil {
        self.disconnected(error?.localizedDescription, connection: connection)
        return
      }
      self.receive(on: connection, buffer: nextBuffer)
    }
  }

  private func disconnected(_ reason: String?, connection finishedConnection: NWConnection) {
    let result = lock.withLock { () -> (handled: Bool, shouldRestart: Bool) in
      guard connection === finishedConnection else { return (false, false) }
      isConnected = false
      connection = nil
      return (true, wantsConnection)
    }
    guard result.handled else { return }
    emit(.state(reason.map(BridgeConnectionState.failed) ?? .disconnected))
    if result.shouldRestart {
      queue.asyncAfter(deadline: .now() + 0.75) { [weak self] in
        guard let self, self.lock.withLock({ self.wantsConnection }) else { return }
        self.start()
      }
    }
  }

  private func emit(_ event: BridgeClientEvent) {
    lock.withLock { eventHandler }?(event)
  }

  private static func preferredSelection(
    in results: Set<NWBrowser.Result>,
    preference: ConnectionPreference
  ) -> (result: NWBrowser.Result, interface: NWInterface?)? {
    guard preference != .nearbyOnly && preference != .remoteOnly else { return nil }
    let selections = results.flatMap { result in
      result.interfaces.map { (result: result, interface: Optional($0)) }
        + (result.interfaces.isEmpty ? [(result: result, interface: nil)] : [])
    }
    return selections.sorted { lhs, rhs in
      let lhsScore = interfaceScore(lhs.interface?.type, preference: preference)
      let rhsScore = interfaceScore(rhs.interface?.type, preference: preference)
      if lhsScore != rhsScore { return lhsScore > rhsScore }
      return String(describing: lhs.result.endpoint) < String(describing: rhs.result.endpoint)
    }.first
  }

  private static func interfaceScore(
    _ type: NWInterface.InterfaceType?, preference: ConnectionPreference
  ) -> Int {
    switch (preference, type) {
    case (.preferWiFi, .wifi): 30
    case (.preferWiFi, .wiredEthernet): 20
    case (_, .wiredEthernet): 30
    case (_, .wifi): 20
    default: 10
    }
  }
}

extension WiFiClient: BridgeClientTransport {}
