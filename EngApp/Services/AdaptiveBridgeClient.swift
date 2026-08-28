import Foundation

final class AdaptiveBridgeClient: @unchecked Sendable {
  private let nearby: NearbyClient
  private let wifi = WiFiClient()
  private let lock = NSLock()
  private var eventHandler: (@Sendable (BridgeClientEvent) -> Void)?

  init(displayName: String) {
    nearby = NearbyClient(displayName: displayName)
    nearby.setEventHandler { [weak self] event in self?.relay(event, fromWiFi: false) }
    wifi.setEventHandler { [weak self] event in self?.relay(event, fromWiFi: true) }
  }

  var kind: BridgeTransportKind { wifi.connected ? .wifiDirect : .nearbyAuto }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { eventHandler = handler }
  }

  func start() { nearby.start() }

  func stop() {
    wifi.stop()
    nearby.stop()
  }

  func install(_ bootstrap: TransportBootstrap) { wifi.install(bootstrap) }

  func send(_ envelope: BridgeEnvelope) throws {
    if wifi.connected {
      do {
        try wifi.send(envelope)
        return
      } catch {
        // Fall back to the encrypted nearby session.
      }
    }
    try nearby.send(envelope)
  }

  private func relay(_ event: BridgeClientEvent, fromWiFi: Bool) {
    if !fromWiFi, wifi.connected, case .state = event { return }
    lock.withLock { eventHandler }?(event)
  }
}

extension AdaptiveBridgeClient: BridgeClientTransport {}
