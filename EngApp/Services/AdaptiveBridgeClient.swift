import EngCore
import Foundation

final class AdaptiveBridgeClient: @unchecked Sendable {
  private let nearby: NearbyClient
  private let wifi: WiFiClient
  private let remote: RemoteRelayClient
  private let lock = NSLock()
  private var eventHandler: (@Sendable (BridgeClientEvent) -> Void)?
  private var preference = ConnectionPreference.automatic
  private var isStarted = false

  init(displayName: String, deviceID: UUID) {
    nearby = NearbyClient(displayName: displayName)
    wifi = WiFiClient(deviceID: deviceID, deviceName: displayName)
    remote = RemoteRelayClient(deviceID: deviceID, deviceName: displayName)
    nearby.setEventHandler { [weak self] event in self?.relay(event, fromWiFi: false) }
    wifi.setEventHandler { [weak self] event in self?.relay(event, fromWiFi: true) }
    remote.setEventHandler { [weak self] event in self?.relayRemote(event) }
  }

  var kind: BridgeTransportKind {
    if wifi.connected { return .wifiDirect }
    if remote.connected { return .remoteRelay }
    return .nearbyAuto
  }
  var identityPublicKey: Data? { wifi.identityPublicKey }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { eventHandler = handler }
  }

  func start() {
    lock.withLock { isStarted = true }
    applyConnectionPreference()
  }

  func stop() {
    lock.withLock { isStarted = false }
    wifi.stop()
    nearby.stop()
    remote.stop()
  }

  func setConnectionPreference(_ preference: ConnectionPreference) {
    let shouldApply = lock.withLock { () -> Bool in
      self.preference = preference
      return isStarted
    }
    wifi.setConnectionPreference(preference)
    if shouldApply { applyConnectionPreference() }
  }

  func install(_ bootstrap: TransportBootstrap) { wifi.install(bootstrap) }

  func configureRemote(_ configuration: RemoteRelayConfiguration?) {
    remote.configure(configuration)
  }

  func send(_ envelope: BridgeEnvelope) throws {
    if wifi.connected {
      do {
        try wifi.send(envelope)
        return
      } catch {
        // Fall back to the encrypted nearby session.
      }
    }
    if remote.connected {
      do { try remote.send(envelope); return } catch {}
    }
    try nearby.send(envelope)
  }

  private func relayRemote(_ event: BridgeClientEvent) {
    if wifi.connected, case .state = event { return }
    if remote.connected, case .state(.connected) = event { nearby.stop() }
    lock.withLock { eventHandler }?(event)
  }

  private func relay(_ event: BridgeClientEvent, fromWiFi: Bool) {
    if fromWiFi, case .state(.connected) = event { nearby.stop() }
    if fromWiFi, case .state(.disconnected) = event { nearby.start() }
    if fromWiFi, case .state(.failed) = event { nearby.start() }
    if !fromWiFi, wifi.connected, case .state = event { return }
    lock.withLock { eventHandler }?(event)
  }

  private func applyConnectionPreference() {
    let preference = lock.withLock { self.preference }
    wifi.setConnectionPreference(preference)
    if preference == .remoteOnly {
      wifi.stop()
      nearby.stop()
      remote.start()
    } else if preference == .nearbyOnly {
      wifi.stop()
      nearby.start()
      remote.stop()
    } else {
      wifi.start()
      nearby.start()
      remote.start()
    }
  }
}

extension AdaptiveBridgeClient: BridgeClientTransport {}
