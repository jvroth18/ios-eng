import EngCore
import Foundation
@preconcurrency import MultipeerConnectivity

public final class NearbyServer: NSObject, @unchecked Sendable {
  public static let serviceType = "ios-eng"
  public static let maximumFrameBytes = 2 * 1_024 * 1_024

  private let peerID: MCPeerID
  private let session: MCSession
  private let advertiser: MCNearbyServiceAdvertiser
  private let lock = NSLock()
  private var envelopeHandler: (@Sendable (String, BridgeEnvelope) -> Void)?
  private var stateHandler: (@Sendable (String, BridgeTransportPeerState) -> Void)?
  // Peer names handed to the coordinator must be unique per connection. Two iPhones
  // with the same display name would otherwise share one pairing/subscription slot,
  // so each MCPeerID gets a process-unique suffix on first sight.
  private var peerNames: [MCPeerID: String] = [:]
  private var peerSequence = 0

  public let kind = BridgeTransportKind.nearbyAuto

  public init(displayName: String = Host.current().localizedName ?? "Eng Bridge") {
    let safeName = String(displayName.prefix(60))
    peerID = MCPeerID(displayName: safeName)
    session = MCSession(
      peer: peerID,
      securityIdentity: nil,
      encryptionPreference: .required
    )
    advertiser = MCNearbyServiceAdvertiser(
      peer: peerID,
      discoveryInfo: ["version": String(BridgeEnvelope.currentProtocolVersion)],
      serviceType: Self.serviceType
    )
    super.init()
    session.delegate = self
    advertiser.delegate = self
  }

  public func setHandlers(
    envelope: @escaping @Sendable (String, BridgeEnvelope) -> Void,
    state: @escaping @Sendable (String, BridgeTransportPeerState) -> Void
  ) {
    lock.withLock {
      envelopeHandler = envelope
      stateHandler = state
    }
  }

  public func start() {
    advertiser.startAdvertisingPeer()
  }

  public func stop() {
    advertiser.stopAdvertisingPeer()
    session.disconnect()
  }

  public var connectedPeerNames: [String] {
    session.connectedPeers.map(name(for:))
  }

  public func send(_ envelope: BridgeEnvelope, to peerName: String) throws {
    let peers = session.connectedPeers.filter { name(for: $0) == peerName }
    guard !peers.isEmpty else {
      throw BridgeError(
        code: "peer_disconnected",
        message: "The iPhone is no longer connected.",
        recoverable: true
      )
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(envelope)
    guard data.count <= Self.maximumFrameBytes else {
      throw BridgeError(
        code: "frame_too_large",
        message: "The bridge frame exceeds the 2 MB safety limit.",
        recoverable: false
      )
    }
    try session.send(data, toPeers: peers, with: .reliable)
  }

  private func name(for peer: MCPeerID) -> String {
    lock.withLock {
      if let name = peerNames[peer] { return name }
      peerSequence += 1
      let name = "\(peer.displayName)#\(peerSequence)"
      peerNames[peer] = name
      return name
    }
  }

  private func forget(_ peer: MCPeerID) {
    _ = lock.withLock { peerNames.removeValue(forKey: peer) }
  }
}

extension NearbyServer: MCNearbyServiceAdvertiserDelegate {
  public func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext context: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    invitationHandler(true, session)
  }

  public func advertiser(
    _ advertiser: MCNearbyServiceAdvertiser,
    didNotStartAdvertisingPeer error: any Error
  ) {
    FileHandle.standardError.write(
      Data("Eng nearby advertising failed: \(error.localizedDescription)\n".utf8)
    )
  }
}

extension NearbyServer: MCSessionDelegate {
  public func session(
    _ session: MCSession,
    peer peerID: MCPeerID,
    didChange state: MCSessionState
  ) {
    let handler = lock.withLock { stateHandler }
    let transportState: BridgeTransportPeerState
    switch state {
    case .notConnected: transportState = .disconnected
    case .connecting: transportState = .connecting
    case .connected: transportState = .connected
    @unknown default: transportState = .disconnected
    }
    let name = name(for: peerID)
    handler?(name, transportState)
    if transportState == .disconnected { forget(peerID) }
  }

  public func session(
    _ session: MCSession,
    didReceive data: Data,
    fromPeer peerID: MCPeerID
  ) {
    guard data.count <= Self.maximumFrameBytes else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let envelope = try? decoder.decode(BridgeEnvelope.self, from: data) else { return }
    let handler = lock.withLock { envelopeHandler }
    handler?(name(for: peerID), envelope)
  }

  public func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  public func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {}

  public func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: (any Error)?
  ) {}

  public func session(
    _ session: MCSession,
    didReceiveCertificate certificate: [Any]?,
    fromPeer peerID: MCPeerID,
    certificateHandler: @escaping (Bool) -> Void
  ) {
    certificateHandler(true)
  }
}

extension NearbyServer: BridgeServerTransport {}
