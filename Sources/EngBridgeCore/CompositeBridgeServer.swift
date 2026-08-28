import EngCore
import Foundation

public final class CompositeBridgeServer: @unchecked Sendable {
  private let transports: [any BridgeServerTransport]
  private let lock = NSLock()
  private var envelopeHandler: (@Sendable (String, BridgeEnvelope) -> Void)?
  private var stateHandler: (@Sendable (String, BridgeTransportPeerState) -> Void)?

  public let kind = BridgeTransportKind.nearbyAuto

  public init(_ transports: [any BridgeServerTransport]) {
    self.transports = transports
  }

  public func setHandlers(
    envelope: @escaping @Sendable (String, BridgeEnvelope) -> Void,
    state: @escaping @Sendable (String, BridgeTransportPeerState) -> Void
  ) {
    lock.withLock {
      envelopeHandler = envelope
      stateHandler = state
    }
    for (index, transport) in transports.enumerated() {
      transport.setHandlers(
        envelope: { [weak self] peer, envelope in
          self?.lock.withLock { self?.envelopeHandler }?("\(index):\(peer)", envelope)
        },
        state: { [weak self] peer, state in
          self?.lock.withLock { self?.stateHandler }?("\(index):\(peer)", state)
        }
      )
    }
  }

  public func start() {
    for transport in transports { transport.start() }
  }

  public func stop() {
    for transport in transports { transport.stop() }
  }

  public var connectedPeerNames: [String] {
    transports.enumerated().flatMap { index, transport in
      transport.connectedPeerNames.map { "\(index):\($0)" }
    }
  }

  public func send(_ envelope: BridgeEnvelope, to peerName: String) throws {
    let parts = peerName.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, let index = Int(parts[0]), transports.indices.contains(index) else {
      throw BridgeError(
        code: "transport_route", message: "The bridge transport route is invalid.",
        recoverable: true)
    }
    try transports[index].send(envelope, to: parts[1])
  }
}

extension CompositeBridgeServer: BridgeServerTransport {}
