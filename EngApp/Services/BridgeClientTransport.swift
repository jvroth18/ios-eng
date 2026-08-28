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

protocol BridgeClientTransport: AnyObject, Sendable {
  var kind: BridgeTransportKind { get }
  var identityPublicKey: Data? { get }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void)
  func start()
  func stop()
  func send(_ envelope: BridgeEnvelope) throws
  func install(_ bootstrap: TransportBootstrap)
}

extension BridgeClientTransport {
  func install(_ bootstrap: TransportBootstrap) {}
}
