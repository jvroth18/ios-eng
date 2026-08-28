import EngCore
import Foundation
@preconcurrency import Network

final class WiFiClient: @unchecked Sendable {
  private let queue = DispatchQueue(label: "dev.jvroth.eng.wifi-client")
  private let lock = NSLock()
  private var browser: NWBrowser?
  private var connection: NWConnection?
  private var bootstrap: TransportBootstrap?
  private var eventHandler: (@Sendable (BridgeClientEvent) -> Void)?
  private var isConnected = false

  let kind = BridgeTransportKind.wifiDirect

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
    guard lock.withLock({ bootstrap?.isValid() == true }) else { return }
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    let browser = NWBrowser(
      for: .bonjour(type: "_ios-eng-fast._tcp", domain: nil), using: parameters)
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self, let endpoint = results.first?.endpoint else { return }
      self.connect(to: endpoint, parameters: parameters)
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
      return values
    }
    values.0?.cancel()
    values.1?.cancel()
  }

  func send(_ envelope: BridgeEnvelope) throws {
    guard
      let (connection, bootstrap) = lock.withLock({ () -> (NWConnection, TransportBootstrap)? in
        guard isConnected, let connection, let bootstrap else { return nil }
        return (connection, bootstrap)
      })
    else {
      throw BridgeError(
        code: "wifi_disconnected", message: "The direct Wi-Fi link is not connected.",
        recoverable: true)
    }
    let packet = try SecureTransportCodec.seal(envelope, using: bootstrap)
    connection.send(
      content: try NewlineFrameBuffer.encode(packet), completion: .contentProcessed { _ in })
  }

  var connected: Bool { lock.withLock { isConnected } }

  private func connect(to endpoint: NWEndpoint, parameters: NWParameters) {
    let shouldConnect = lock.withLock { self.connection == nil }
    guard shouldConnect else { return }
    let connection = NWConnection(to: endpoint, using: parameters)
    lock.withLock { self.connection = connection }
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      switch state {
      case .ready:
        self.lock.withLock {
          self.isConnected = true
          self.browser?.cancel()
          self.browser = nil
        }
        self.emit(.state(.connected("Mac · Direct Wi-Fi")))
        self.receive(on: connection, buffer: NewlineFrameBuffer())
      case .failed(let error): self.disconnected(error.localizedDescription)
      case .cancelled: self.disconnected(nil)
      default: break
      }
    }
    connection.start(queue: queue)
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
        self.disconnected(error?.localizedDescription)
        return
      }
      self.receive(on: connection, buffer: nextBuffer)
    }
  }

  private func disconnected(_ reason: String?) {
    let shouldRestart = lock.withLock { () -> Bool in
      isConnected = false
      connection = nil
      return bootstrap?.isValid() == true
    }
    emit(.state(reason.map(BridgeConnectionState.failed) ?? .disconnected))
    if shouldRestart { start() }
  }

  private func emit(_ event: BridgeClientEvent) {
    lock.withLock { eventHandler }?(event)
  }
}

extension WiFiClient: BridgeClientTransport {}
