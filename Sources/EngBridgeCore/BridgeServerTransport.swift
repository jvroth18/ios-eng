import EngCore
import Foundation

public protocol BridgeServerTransport: AnyObject, Sendable {
  var kind: BridgeTransportKind { get }
  var connectedPeerNames: [String] { get }

  func setHandlers(
    envelope: @escaping @Sendable (String, BridgeEnvelope) -> Void,
    state: @escaping @Sendable (String, BridgeTransportPeerState) -> Void
  )
  func start()
  func stop()
  func send(_ envelope: BridgeEnvelope, to peerName: String) throws
}
