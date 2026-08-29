import EngCore
import Foundation

public struct RelayHTTPRequest: Equatable, Sendable {
  public let method: String
  public let path: String
  public let headers: [String: String]
  public let body: Data

  public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
    self.method = method
    self.path = path
    self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
    self.body = body
  }
}

public struct RelayHTTPResponse: Equatable, Sendable {
  public let status: Int
  public let body: Data
  public let contentType: String

  public init(status: Int, body: Data = Data(), contentType: String = "application/json") {
    self.status = status
    self.body = body
    self.contentType = contentType
  }
}

public actor RelayHTTPRouter {
  private let broker: OpaqueRelayBroker

  public init(broker: OpaqueRelayBroker) { self.broker = broker }

  public func response(to request: RelayHTTPRequest) async -> RelayHTTPResponse {
    if request.method == "GET", request.path == "/healthz" {
      return RelayHTTPResponse(status: 200, body: Data("{\"status\":\"ok\"}".utf8))
    }
    let components = request.path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count == 4, components[0] == "v1", components[1] == "channels",
      let channelID = UUID(uuidString: String(components[2])),
      let role = RelayPeerRole(rawValue: String(components[3])),
      let authorization = request.headers["authorization"],
      authorization.hasPrefix("Bearer ")
    else { return RelayHTTPResponse(status: 404, body: errorBody("not_found")) }
    let token = String(authorization.dropFirst("Bearer ".count))

    do {
      switch request.method {
      case "POST":
        guard request.body.count <= SecureTransportCodec.maximumPacketBytes * 2 else {
          return RelayHTTPResponse(status: 413, body: errorBody("frame_too_large"))
        }
        let frame = try JSONDecoder().decode(RelayOpaqueFrame.self, from: request.body)
        try await broker.send(
          frame, from: role, channelID: channelID, bearerToken: token)
        return RelayHTTPResponse(status: 202, body: Data("{\"accepted\":true}".utf8))
      case "GET":
        let frames = try await broker.receive(
          for: role, channelID: channelID, bearerToken: token)
        return RelayHTTPResponse(status: 200, body: try JSONEncoder().encode(frames))
      default:
        return RelayHTTPResponse(status: 405, body: errorBody("method_not_allowed"))
      }
    } catch RelayProtocolError.unauthorized {
      return RelayHTTPResponse(status: 401, body: errorBody("unauthorized"))
    } catch RelayProtocolError.queueFull {
      return RelayHTTPResponse(status: 429, body: errorBody("queue_full"))
    } catch {
      return RelayHTTPResponse(status: 400, body: errorBody("invalid_request"))
    }
  }

  private func errorBody(_ code: String) -> Data { Data("{\"error\":\"\(code)\"}".utf8) }
}

public enum RelayCredentialFile {
  public static func load(from url: URL) throws -> [RelayChannelCredential] {
    let data = try Data(contentsOf: url)
    if let list = try? JSONDecoder().decode([RelayChannelCredential].self, from: data) { return list }
    return [try JSONDecoder().decode(RelayChannelCredential.self, from: data)]
  }

  public static func write(_ credential: RelayChannelCredential, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(credential).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
