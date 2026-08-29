import Darwin
import EngCore
import EngRelayCore
import Foundation
@preconcurrency import Network

@main enum EngRelayMain {
  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      if arguments.first == "issue" {
        let credential = try RelayChannelCredential.generate()
        let output = value(after: "--output", in: arguments).map(URL.init(fileURLWithPath:))
          ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "relay-channel.json")
        try RelayCredentialFile.write(credential, to: output)
        print("Created \(output.path) with mode 0600")
        print("Channel: \(credential.channelID.uuidString)")
        return
      }

      let file = value(after: "--credentials", in: arguments)
        ?? ProcessInfo.processInfo.environment["ENG_RELAY_CREDENTIALS"]
      guard let file else { throw RelayMainError.missingCredentials }
      let port = UInt16(value(after: "--port", in: arguments) ?? "8787") ?? 8787
      let publicBind = arguments.contains("--public-bind")
      let broker = OpaqueRelayBroker()
      for credential in try RelayCredentialFile.load(from: URL(fileURLWithPath: file)) {
        await broker.register(credential)
      }
      let server = try RelayHTTPServer(
        router: RelayHTTPRouter(broker: broker), port: port, publicBind: publicBind)
      try server.start()
      let bindAddress = publicBind ? "0.0.0.0" : "127.0.0.1"
      print("Eng Relay ready on \(bindAddress):\(port)")
      if !publicBind { print("Terminate TLS in front of this loopback listener.") }
      await waitForTerminationSignal()
      server.stop()
    } catch {
      FileHandle.standardError.write(Data("Eng Relay failed: \(error.localizedDescription)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
  }

  private static func waitForTerminationSignal() async {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let stream = AsyncStream<Void>.makeStream()
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    interrupt.setEventHandler { stream.continuation.yield() }
    terminate.setEventHandler { stream.continuation.yield() }
    interrupt.resume(); terminate.resume()
    for await _ in stream.stream { break }
    interrupt.cancel(); terminate.cancel(); stream.continuation.finish()
  }
}

private enum RelayMainError: LocalizedError {
  case missingCredentials
  var errorDescription: String? { "Pass --credentials <relay-channel.json> or set ENG_RELAY_CREDENTIALS." }
}

private final class RelayHTTPServer: @unchecked Sendable {
  private let router: RelayHTTPRouter
  private let queue = DispatchQueue(label: "dev.jvroth.eng.relay")
  private let listener: NWListener

  init(router: RelayHTTPRouter, port: UInt16, publicBind: Bool) throws {
    self.router = router
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(
      host: publicBind ? "0.0.0.0" : "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
    listener = try NWListener(using: parameters)
  }

  func start() throws {
    listener.newConnectionHandler = { [weak self] in self?.accept($0) }
    listener.start(queue: queue)
  }

  func stop() { listener.cancel() }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(on: connection, buffer: Data())
  }

  private func receive(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      var next = buffer
      next.append(data ?? Data())
      if next.count > SecureTransportCodec.maximumPacketBytes * 2 + 16 * 1_024 {
        self.send(.init(status: 413), on: connection); return
      }
      if let request = Self.parse(next) {
        Task { self.send(await self.router.response(to: request), on: connection) }
      } else if complete || error != nil {
        connection.cancel()
      } else {
        self.receive(on: connection, buffer: next)
      }
    }
  }

  private func send(_ response: RelayHTTPResponse, on connection: NWConnection) {
    let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 429: "Too Many Requests"][response.status] ?? "Error"
    var data = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
    data.append(response.body)
    connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
  }

  private static func parse(_ data: Data) -> RelayHTTPRequest? {
    let separator = Data("\r\n\r\n".utf8)
    guard let range = data.range(of: separator),
      let head = String(data: data[..<range.lowerBound], encoding: .utf8)
    else { return nil }
    let lines = head.components(separatedBy: "\r\n")
    let first = lines[0].split(separator: " ")
    guard first.count >= 2 else { return nil }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
    let length = Int(headers["content-length"] ?? "0") ?? 0
    let bodyStart = range.upperBound
    guard data.count >= bodyStart + length else { return nil }
    return RelayHTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers, body: Data(data[bodyStart..<(bodyStart + length)]))
  }
}
