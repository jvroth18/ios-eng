import EngCore
import EngRelayCore
import Foundation
import Testing

@Suite struct RelayHTTPRouterTests {
  @Test func healthAndAuthenticatedRouting() async throws {
    let credential = try RelayChannelCredential.generate()
    let broker = OpaqueRelayBroker()
    await broker.register(credential)
    let router = RelayHTTPRouter(broker: broker)
    #expect(await router.response(to: .init(method: "GET", path: "/healthz")).status == 200)

    let frame = try RelayOpaqueFrame(sequence: 1, payload: Data("opaque".utf8))
    let path = "/v1/channels/\(credential.channelID.uuidString)/phone"
    let sent = await router.response(to: .init(
      method: "POST", path: path,
      headers: ["Authorization": "Bearer \(credential.bearerToken)"],
      body: try JSONEncoder().encode(frame)))
    #expect(sent.status == 202)

    let received = await router.response(to: .init(
      method: "GET", path: path.replacingOccurrences(of: "/phone", with: "/bridge"),
      headers: ["Authorization": "Bearer \(credential.bearerToken)"]))
    #expect(received.status == 200)
    #expect(try JSONDecoder().decode([RelayOpaqueFrame].self, from: received.body) == [frame])
  }

  @Test func rejectsMissingAuthorizationAndOversizedPayload() async throws {
    let credential = try RelayChannelCredential.generate()
    let broker = OpaqueRelayBroker()
    await broker.register(credential)
    let router = RelayHTTPRouter(broker: broker)
    let path = "/v1/channels/\(credential.channelID.uuidString)/phone"
    #expect(await router.response(to: .init(method: "GET", path: path)).status == 404)
    let response = await router.response(to: .init(
      method: "POST", path: path,
      headers: ["Authorization": "Bearer \(credential.bearerToken)"],
      body: Data(repeating: 1, count: SecureTransportCodec.maximumPacketBytes * 2 + 1)))
    #expect(response.status == 413)
  }
}
