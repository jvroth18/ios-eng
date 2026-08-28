import EngCore
import Foundation
@preconcurrency import MultipeerConnectivity
import OSLog

final class NearbyClient: NSObject, @unchecked Sendable {
  static let serviceType = "ios-eng"
  static let maximumFrameBytes = 2 * 1_024 * 1_024
  private static let logger = Logger(subsystem: "dev.jvroth.eng", category: "Nearby")

  private let peerID: MCPeerID
  private let session: MCSession
  private let browser: MCNearbyServiceBrowser
  private let lock = NSLock()
  private var isRunning = false
  private var invitedPeerNames = Set<String>()
  private var eventHandler: (@Sendable (BridgeClientEvent) -> Void)?

  let kind = BridgeTransportKind.nearbyAuto
  let identityPublicKey: Data? = nil

  init(displayName: String) {
    let safeName = String("\(displayName) · Eng".prefix(60))
    peerID = MCPeerID(displayName: safeName)
    session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
    super.init()
    session.delegate = self
    browser.delegate = self
  }

  func setEventHandler(_ handler: @escaping @Sendable (BridgeClientEvent) -> Void) {
    lock.withLock { eventHandler = handler }
  }

  func start() {
    let shouldStart = lock.withLock { () -> Bool in
      guard !isRunning else { return false }
      isRunning = true
      return true
    }
    guard shouldStart else { return }
    trace("Starting encrypted nearby browser for _\(Self.serviceType)._tcp")
    emit(.state(.searching))
    browser.startBrowsingForPeers()
  }

  func stop() {
    lock.withLock { isRunning = false }
    trace("Stopping nearby browser and session")
    browser.stopBrowsingForPeers()
    session.disconnect()
    lock.withLock { invitedPeerNames.removeAll() }
  }

  func send(_ envelope: BridgeEnvelope) throws {
    let peers = session.connectedPeers
    guard !peers.isEmpty else {
      throw BridgeError(
        code: "mac_disconnected",
        message: "The Mac bridge is not connected.",
        recoverable: true
      )
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(envelope)
    guard data.count <= Self.maximumFrameBytes else {
      throw BridgeError(
        code: "frame_too_large",
        message: "This message exceeds the 2 MB bridge limit.",
        recoverable: false
      )
    }
    try session.send(data, toPeers: peers, with: .reliable)
  }

  private func emit(_ event: BridgeClientEvent) {
    let handler = lock.withLock { eventHandler }
    handler?(event)
  }

  private func trace(_ message: String) {
    Self.logger.notice("\(message, privacy: .public)")
    FileHandle.standardError.write(Data("[Eng Nearby] \(message)\n".utf8))
  }
}

extension NearbyClient: BridgeClientTransport {}

extension NearbyClient: MCNearbyServiceBrowserDelegate {
  func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo info: [String: String]?
  ) {
    let shouldInvite = lock.withLock {
      isRunning && invitedPeerNames.insert(peerID.displayName).inserted
    }
    guard shouldInvite else { return }
    trace("Found Mac peer \(peerID.displayName); sending invitation")
    emit(.state(.connecting(peerID.displayName)))
    browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    trace("Lost Mac peer \(peerID.displayName)")
    _ = lock.withLock { invitedPeerNames.remove(peerID.displayName) }
  }

  func browser(
    _ browser: MCNearbyServiceBrowser,
    didNotStartBrowsingForPeers error: any Error
  ) {
    trace("Nearby browser failed: \(error.localizedDescription)")
    emit(.state(.failed(error.localizedDescription)))
  }
}

extension NearbyClient: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    trace("Session with \(peerID.displayName) changed to \(state.rawValue)")
    switch state {
    case .notConnected:
      let shouldRestart = lock.withLock { () -> Bool in
        invitedPeerNames.remove(peerID.displayName)
        return isRunning
      }
      guard shouldRestart else { return }
      emit(.state(.disconnected))
      browser.stopBrowsingForPeers()
      trace("Restarting nearby discovery after failed session")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
        guard let self, self.lock.withLock({ self.isRunning }) else { return }
        self.emit(.state(.searching))
        self.browser.startBrowsingForPeers()
      }
    case .connecting:
      emit(.state(.connecting(peerID.displayName)))
    case .connected:
      browser.stopBrowsingForPeers()
      emit(.state(.connected(peerID.displayName)))
    @unknown default:
      emit(.state(.disconnected))
    }
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    guard data.count <= Self.maximumFrameBytes else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let envelope = try? decoder.decode(BridgeEnvelope.self, from: data) else { return }
    emit(.envelope(envelope))
  }

  func session(
    _ session: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {}

  func session(
    _ session: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {}

  func session(
    _ session: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: (any Error)?
  ) {}

  func session(
    _ session: MCSession,
    didReceiveCertificate certificate: [Any]?,
    fromPeer peerID: MCPeerID,
    certificateHandler: @escaping (Bool) -> Void
  ) {
    certificateHandler(true)
  }
}
