import Foundation

public enum AppServerInbound: Equatable, Sendable {
  case notification(method: String, params: JSONValue)
  case request(id: JSONValue, method: String, params: JSONValue)
}

public struct AppServerFailure: Error, Equatable, Sendable, CustomStringConvertible,
  LocalizedError
{
  public let code: Int?
  public let message: String

  public init(code: Int? = nil, message: String) {
    self.code = code
    self.message = message
  }

  public var description: String {
    if let code { return "Codex App Server error \(code): \(message)" }
    return "Codex App Server error: \(message)"
  }

  public var errorDescription: String? { description }
}

public actor AppServerConnection {
  public nonisolated let events: AsyncStream<AppServerInbound>

  private let eventContinuation: AsyncStream<AppServerInbound>.Continuation
  private let session: URLSession
  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var pending: [String: CheckedContinuation<JSONValue, any Error>] = [:]
  private var nextRequestID: UInt64 = 0

  public init(session: URLSession = .shared) {
    let stream = AsyncStream<AppServerInbound>.makeStream()
    events = stream.stream
    eventContinuation = stream.continuation
    self.session = session
  }

  deinit {
    eventContinuation.finish()
  }

  public func connect(to url: URL) async throws {
    guard socket == nil else { return }
    let socket = session.webSocketTask(with: url)
    self.socket = socket
    socket.resume()
    receiveTask = Task { [weak self] in
      await self?.receiveLoop(socket)
    }

    _ = try await request(
      method: "initialize",
      params: [
        "clientInfo": [
          "name": "ios_eng_bridge",
          "title": "Eng Bridge",
          "version": "0.1.0",
        ],
        "capabilities": ["experimentalApi": true],
      ]
    )
    try await notify(method: "initialized", params: [:])
  }

  public func request(method: String, params: JSONValue = [:]) async throws -> JSONValue {
    guard socket != nil else {
      throw AppServerFailure(message: "Not connected")
    }
    nextRequestID += 1
    let id = "eng:\(nextRequestID)"
    let message: JSONValue = [
      "method": .string(method),
      "id": .string(id),
      "params": params,
    ]
    let data = try JSONEncoder().encode(message)

    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      Task { [weak self] in
        guard let self else { return }
        do {
          try await self.send(data)
        } catch {
          await self.failPending(id: id, error: error)
        }
      }
    }
  }

  public func notify(method: String, params: JSONValue = [:]) async throws {
    let message: JSONValue = [
      "method": .string(method),
      "params": params,
    ]
    try await send(JSONEncoder().encode(message))
  }

  public func respond(id: JSONValue, result: JSONValue) async throws {
    let message: JSONValue = ["id": id, "result": result]
    try await send(JSONEncoder().encode(message))
  }

  public func disconnect() {
    receiveTask?.cancel()
    receiveTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    let error = AppServerFailure(message: "Connection closed")
    for continuation in pending.values {
      continuation.resume(throwing: error)
    }
    pending.removeAll()
  }

  private func send(_ data: Data) async throws {
    guard let socket else { throw AppServerFailure(message: "Not connected") }
    guard let text = String(data: data, encoding: .utf8) else {
      throw AppServerFailure(message: "Could not encode a JSON-RPC text frame")
    }
    try await socket.send(.string(text))
  }

  private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
    do {
      while !Task.isCancelled {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .data(let value):
          data = value
        case .string(let value):
          guard let encoded = value.data(using: .utf8) else { continue }
          data = encoded
        @unknown default:
          continue
        }
        receive(data)
      }
    } catch {
      if !Task.isCancelled {
        connectionFailed(error)
      }
    }
  }

  private func receive(_ data: Data) {
    guard let message = try? JSONDecoder().decode(JSONValue.self, from: data),
      let object = message.objectValue
    else {
      return
    }

    if let id = object["id"]?.stringValue, let continuation = pending.removeValue(forKey: id) {
      if let result = object["result"] {
        continuation.resume(returning: result)
      } else {
        let error = object["error"]
        continuation.resume(
          throwing: AppServerFailure(
            code: error?["code"]?.intValue,
            message: error?["message"]?.stringValue ?? "Unknown request failure"
          )
        )
      }
      return
    }

    guard let method = object["method"]?.stringValue else { return }
    let params = object["params"] ?? [:]
    if let id = object["id"] {
      eventContinuation.yield(.request(id: id, method: method, params: params))
    } else {
      eventContinuation.yield(.notification(method: method, params: params))
    }
  }

  private func failPending(id: String, error: any Error) {
    pending.removeValue(forKey: id)?.resume(throwing: error)
  }

  private func connectionFailed(_ error: any Error) {
    socket = nil
    let failure = AppServerFailure(message: error.localizedDescription)
    for continuation in pending.values {
      continuation.resume(throwing: failure)
    }
    pending.removeAll()
  }
}
