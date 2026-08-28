import EngCore
import Foundation

enum BridgeConnectionState: Equatable, Sendable {
  case searching
  case connecting(String)
  case connected(String)
  case disconnected
  case failed(String)
}

enum BridgeClientEvent: Sendable {
  case state(BridgeConnectionState)
  case envelope(BridgeEnvelope)
}

enum ConnectionPreference: String, CaseIterable, Identifiable, Sendable {
  case automatic
  case preferUSBC
  case preferWiFi
  case nearbyOnly

  var id: String { rawValue }

  var label: String {
    switch self {
    case .automatic: "Automatic"
    case .preferUSBC: "USB-C first"
    case .preferWiFi: "Wi-Fi first"
    case .nearbyOnly: "Nearby only"
    }
  }

  var detail: String {
    switch self {
    case .automatic: "Use the best direct route, then fall back to Nearby."
    case .preferUSBC: "Use the wired USB-C route when present; Nearby remains available."
    case .preferWiFi: "Use direct Wi-Fi when present; Nearby remains available."
    case .nearbyOnly: "Disable direct local discovery and use the encrypted Nearby session."
    }
  }
}

protocol BridgeClientTransport: AnyObject, Sendable {
  var kind: BridgeTransportKind { get }
  var identityPublicKey: Data? { get }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void)
  func start()
  func stop()
  func send(_ envelope: BridgeEnvelope) throws
  func install(_ bootstrap: TransportBootstrap)
  func setConnectionPreference(_ preference: ConnectionPreference)
}

extension BridgeClientTransport {
  func install(_ bootstrap: TransportBootstrap) {}
  func setConnectionPreference(_ preference: ConnectionPreference) {}
}
