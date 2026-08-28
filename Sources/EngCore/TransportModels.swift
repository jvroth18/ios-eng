import Foundation

public enum BridgeTransportKind: String, Codable, CaseIterable, Equatable, Sendable {
  case nearbyAuto
  case wifiDirect
  case sshTunnel

  public var title: String {
    switch self {
    case .nearbyAuto: "Nearby Auto"
    case .wifiDirect: "Direct Local"
    case .sshTunnel: "SSH Tunnel"
    }
  }

  public var securityLabel: String {
    switch self {
    case .nearbyAuto: "Apple encrypted session"
    case .wifiDirect: "Encrypted direct session"
    case .sshTunnel: "SSH host-key verified"
    }
  }

  public var detail: String {
    switch self {
    case .nearbyAuto:
      "Automatically uses Bluetooth, peer-to-peer Wi-Fi, or local Wi-Fi. Apple does not expose the selected bearer."
    case .wifiDirect:
      "Prefers a USB-C or wired network path when available, then local or peer-to-peer Wi-Fi, with Curve25519 key agreement and authenticated encryption."
    case .sshTunnel:
      "Carries the same bounded Eng protocol through a host-key-verified SSH connection."
    }
  }
}

public enum BridgeTransportPeerState: Equatable, Sendable {
  case connecting
  case connected
  case disconnected
}
