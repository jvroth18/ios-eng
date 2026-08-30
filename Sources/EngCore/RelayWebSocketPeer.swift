import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum RelayWebSocketEvent: Equatable, Sendable {
  case ready(peerConnected: Bool)
  case peerConnected(Bool)
}

private struct RelayWebSocketConnectionFailure: LocalizedError {
  let underlying: NSError
  let statusCode: Int?

  var errorDescription: String? {
    let status = statusCode.map { ", HTTP \($0)" } ?? ""
    return
      "WebSocket failed (\(underlying.domain) \(underlying.code)\(status)): \(underlying.localizedDescription)"
  }
}

public final class RelayWebSocketPeer: @unchecked Sendable {
  private struct Control: Decodable {
    let type: String
    let peerConnected: Bool?
    let connected: Bool?
  }

  private let configuration: RemoteRelayConfiguration
  private let role: RelayPeerRole
  private let session: URLSession
  private let lock = NSLock()
  private var socket: URLSessionWebSocketTask?
  private var connectionTask: Task<Void, Never>?
  private var payloadHandler: (@Sendable (Result<Data, Error>) -> Void)?
  private var controlHandler: (@Sendable (RelayWebSocketEvent) -> Void)?
  private var wantsConnection = false

  public init(
    configuration: RemoteRelayConfiguration,
    role: RelayPeerRole,
    session: URLSession = .shared
  ) {
    self.configuration = configuration
    self.role = role
    self.session = session
  }

  public func start(
    payload: @escaping @Sendable (Result<Data, Error>) -> Void,
    control: @escaping @Sendable (RelayWebSocketEvent) -> Void = { _ in }
  ) {
    stop()
    lock.withLock {
      wantsConnection = true
      payloadHandler = payload
      controlHandler = control
    }
    connectionTask = Task { [weak self] in await self?.connectionLoop() }
  }

  public func stop() {
    let values = lock.withLock { () -> (URLSessionWebSocketTask?, Task<Void, Never>?) in
      wantsConnection = false
      let values = (socket, connectionTask)
      socket = nil
      connectionTask = nil
      payloadHandler = nil
      controlHandler = nil
      return values
    }
    values.0?.cancel(with: .goingAway, reason: nil)
    values.1?.cancel()
  }

  public func send(_ payload: Data) async throws {
    guard !payload.isEmpty, payload.count <= SecureTransportCodec.maximumPacketBytes else {
      throw RelayProtocolError.invalidFrame
    }
    guard let socket = lock.withLock({ self.socket }) else { throw RemoteRelayError.stopped }
    try await socket.send(.data(payload))
  }

  private func connectionLoop() async {
    while !Task.isCancelled, lock.withLock({ wantsConnection }) {
      let current = session.webSocketTask(with: request())
      lock.withLock { socket = current }
      current.resume()
      do {
        let keepAliveTask = Task { await keepAlive(current) }
        defer { keepAliveTask.cancel() }
        while !Task.isCancelled {
          switch try await current.receive() {
          case .data(let data): emitPayload(.success(data))
          case .string(let text): try emitControl(text)
          @unknown default: throw RemoteRelayError.invalidResponse
          }
        }
      } catch is CancellationError {
        return
      } catch {
        let failure = RelayWebSocketConnectionFailure(
          underlying: error as NSError,
          statusCode: (current.response as? HTTPURLResponse)?.statusCode)
        let shouldRetry = lock.withLock { () -> Bool in
          if socket === current { socket = nil }
          return wantsConnection
        }
        if shouldRetry {
          emitPayload(.failure(failure))
          try? await Task.sleep(for: .seconds(2))
        }
      }
    }
  }

  private func request() -> URLRequest {
    var components = URLComponents(
      url: configuration.baseURL.appending(path: "v1/connect"),
      resolvingAgainstBaseURL: false)!
    components.scheme = configuration.baseURL.scheme == "http" ? "ws" : "wss"
    components.queryItems = [
      URLQueryItem(name: "channel", value: configuration.credential.channelID.uuidString),
      URLQueryItem(name: "role", value: role.rawValue),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue(
      "Bearer \(configuration.credential.bearerToken)",
      forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 120
    return request
  }

  private func keepAlive(_ socket: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(20))
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          socket.sendPing { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          }
        }
      } catch is CancellationError {
        return
      } catch {
        socket.cancel(with: .goingAway, reason: nil)
        return
      }
    }
  }

  private func emitControl(_ text: String) throws {
    let control = try JSONDecoder().decode(Control.self, from: Data(text.utf8))
    let event: RelayWebSocketEvent
    switch control.type {
    case "relay.ready": event = .ready(peerConnected: control.peerConnected ?? false)
    case "relay.peer": event = .peerConnected(control.connected ?? false)
    case "relay.peer_unavailable": event = .peerConnected(false)
    default: throw RemoteRelayError.invalidResponse
    }
    lock.withLock { controlHandler }?(event)
  }

  private func emitPayload(_ result: Result<Data, Error>) {
    lock.withLock { payloadHandler }?(result)
  }
}
