import EngCore
import EngRelayCore
import Foundation
import Testing

@Suite struct OpaqueRelayBrokerTests {
  @Test func routesOpaqueFramesOnlyToTheOppositePeer() async throws {
    let credential = try RelayChannelCredential.generate()
    let broker = OpaqueRelayBroker()
    await broker.register(credential)
    let frame = try RelayOpaqueFrame(sequence: 7, payload: Data("ciphertext".utf8))

    try await broker.send(
      frame, from: .phone, channelID: credential.channelID,
      bearerToken: credential.bearerToken)

    #expect(try await broker.receive(
      for: .phone, channelID: credential.channelID,
      bearerToken: credential.bearerToken).isEmpty)
    #expect(try await broker.receive(
      for: .bridge, channelID: credential.channelID,
      bearerToken: credential.bearerToken) == [frame])
  }

  @Test func rejectsWrongCredentialsAndBoundedQueueOverflow() async throws {
    let credential = try RelayChannelCredential.generate()
    let broker = OpaqueRelayBroker(limits: .init(maximumQueuedFramesPerPeer: 1))
    await broker.register(credential)
    let frame = try RelayOpaqueFrame(sequence: 1, payload: Data([1]))

    await #expect(throws: RelayProtocolError.unauthorized) {
      try await broker.send(frame, from: .phone, channelID: credential.channelID, bearerToken: "wrong")
    }
    try await broker.send(
      frame, from: .phone, channelID: credential.channelID,
      bearerToken: credential.bearerToken)
    await #expect(throws: RelayProtocolError.queueFull) {
      try await broker.send(frame, from: .phone, channelID: credential.channelID, bearerToken: credential.bearerToken)
    }
  }

  @Test func expiresIdleChannels() async throws {
    let credential = try RelayChannelCredential.generate()
    let start = Date(timeIntervalSince1970: 100)
    let broker = OpaqueRelayBroker(limits: .init(idleChannelLifetime: 10))
    await broker.register(credential, now: start)
    await broker.removeExpired(now: start.addingTimeInterval(11))

    await #expect(throws: RelayProtocolError.unauthorized) {
      try await broker.receive(
        for: .phone, channelID: credential.channelID,
        bearerToken: credential.bearerToken, now: start.addingTimeInterval(11))
    }
  }
}
