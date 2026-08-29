import CryptoKit
import EngCore
import Foundation

public actor OpaqueRelayBroker {
  public struct Limits: Equatable, Sendable {
    public let maximumQueuedFramesPerPeer: Int
    public let idleChannelLifetime: TimeInterval

    public init(maximumQueuedFramesPerPeer: Int = 256, idleChannelLifetime: TimeInterval = 24 * 60 * 60) {
      self.maximumQueuedFramesPerPeer = maximumQueuedFramesPerPeer
      self.idleChannelLifetime = idleChannelLifetime
    }
  }

  private struct Channel: Sendable {
    let tokenDigest: Data
    var queues: [RelayPeerRole: [RelayOpaqueFrame]]
    var lastActivity: Date
  }

  private let limits: Limits
  private var channels: [UUID: Channel] = [:]

  public init(limits: Limits = Limits()) { self.limits = limits }

  public func register(_ credential: RelayChannelCredential, now: Date = Date()) {
    channels[credential.channelID] = Channel(
      tokenDigest: credential.tokenDigest,
      queues: [.phone: [], .bridge: []],
      lastActivity: now
    )
  }

  public func send(
    _ frame: RelayOpaqueFrame,
    from role: RelayPeerRole,
    channelID: UUID,
    bearerToken: String,
    now: Date = Date()
  ) throws {
    try authorize(channelID: channelID, bearerToken: bearerToken, now: now)
    guard var channel = channels[channelID] else { throw RelayProtocolError.unauthorized }
    let recipient = role.opposite
    guard channel.queues[recipient, default: []].count < limits.maximumQueuedFramesPerPeer else {
      throw RelayProtocolError.queueFull
    }
    channel.queues[recipient, default: []].append(frame)
    channel.lastActivity = now
    channels[channelID] = channel
  }

  public func receive(
    for role: RelayPeerRole,
    channelID: UUID,
    bearerToken: String,
    maximumFrames: Int = 32,
    now: Date = Date()
  ) throws -> [RelayOpaqueFrame] {
    try authorize(channelID: channelID, bearerToken: bearerToken, now: now)
    guard var channel = channels[channelID] else { throw RelayProtocolError.unauthorized }
    let count = min(max(1, maximumFrames), 64, channel.queues[role, default: []].count)
    let frames = Array(channel.queues[role, default: []].prefix(count))
    channel.queues[role, default: []].removeFirst(count)
    channel.lastActivity = now
    channels[channelID] = channel
    return frames
  }

  public func removeExpired(now: Date = Date()) {
    channels = channels.filter { now.timeIntervalSince($0.value.lastActivity) < limits.idleChannelLifetime }
  }

  private func authorize(channelID: UUID, bearerToken: String, now: Date) throws {
    guard let channel = channels[channelID],
      now.timeIntervalSince(channel.lastActivity) < limits.idleChannelLifetime,
      let supplied = Data(base64Encoded: bearerToken),
      constantTimeEqual(Data(SHA256.hash(data: supplied)), channel.tokenDigest)
    else { throw RelayProtocolError.unauthorized }
  }

  private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
    return difference == 0
  }
}
