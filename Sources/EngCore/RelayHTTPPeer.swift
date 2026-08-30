import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct RemoteRelayConfiguration: Codable, Equatable, Sendable {
  public let baseURL: URL
  public let credential: RelayChannelCredential

  public init(baseURL: URL, credential: RelayChannelCredential) throws {
    guard let scheme = baseURL.scheme?.lowercased(),
      scheme == "https" || (scheme == "http" && Self.isLoopback(baseURL.host))
    else { throw RemoteRelayError.insecureURL }
    self.baseURL = baseURL
    self.credential = credential
  }

  private static func isLoopback(_ host: String?) -> Bool {
    host == "127.0.0.1" || host == "localhost" || host == "::1"
  }
}

public enum RemoteRelayError: Error, Equatable, LocalizedError, Sendable {
  case insecureURL
  case invalidResponse
  case rejected(Int)
  case stopped

  public var errorDescription: String? {
    switch self {
    case .insecureURL: "Remote relay URLs must use HTTPS."
    case .invalidResponse: "The remote relay returned an invalid response."
    case .rejected(let status): "The remote relay rejected the request (HTTP \(status))."
    case .stopped: "The remote relay connection stopped."
    }
  }
}

public final class RelayHTTPPeer: @unchecked Sendable {
  private let configuration: RemoteRelayConfiguration
  private let role: RelayPeerRole
  private let session: URLSession
  private let lock = NSLock()
  private var task: Task<Void, Never>?
  private var handler: (@Sendable (Result<Data, Error>) -> Void)?
  private var sequence: UInt64 = 0

  public init(
    configuration: RemoteRelayConfiguration,
    role: RelayPeerRole,
    session: URLSession = .shared
  ) {
    self.configuration = configuration
    self.role = role
    self.session = session
  }

  public func start(handler: @escaping @Sendable (Result<Data, Error>) -> Void) {
    stop()
    lock.withLock { self.handler = handler }
    task = Task { [weak self] in await self?.pollLoop() }
  }

  public func stop() {
    let old = lock.withLock { () -> Task<Void, Never>? in
      let old = task
      task = nil
      handler = nil
      return old
    }
    old?.cancel()
  }

  public func send(_ payload: Data) async throws {
    let nextSequence = lock.withLock { () -> UInt64 in
      sequence &+= 1
      return sequence
    }
    let frame = try RelayOpaqueFrame(sequence: nextSequence, payload: payload)
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(configuration.credential.bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(frame)
    let (_, response) = try await session.data(for: request)
    try validate(response, accepted: 202)
  }

  private func pollLoop() async {
    while !Task.isCancelled {
      do {
        var request = URLRequest(url: endpointURL)
        request.setValue("Bearer \(configuration.credential.bearerToken)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try validate(response, accepted: 200)
        let frames = try JSONDecoder().decode([RelayOpaqueFrame].self, from: data)
        for frame in frames { emit(.success(frame.payload)) }
        if frames.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
      } catch is CancellationError {
        return
      } catch {
        emit(.failure(error))
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  private var endpointURL: URL {
    configuration.baseURL
      .appending(path: "v1/channels")
      .appending(path: configuration.credential.channelID.uuidString)
      .appending(path: role.rawValue)
  }

  private func validate(_ response: URLResponse, accepted: Int) throws {
    guard let http = response as? HTTPURLResponse else { throw RemoteRelayError.invalidResponse }
    guard http.statusCode == accepted else { throw RemoteRelayError.rejected(http.statusCode) }
  }

  private func emit(_ result: Result<Data, Error>) { lock.withLock { handler }?(result) }
}
