import Darwin
import EngBridgeCore
import EngCore
import Foundation

@main
enum EngBridgeMain {
  static func main() async {
    let arguments = CommandLine.arguments.dropFirst()
    let smoke = arguments.contains("--smoke")
    let port = parsePort(arguments) ?? 47_321
    let host = AppServerHost(port: port)
    let connection = AppServerConnection()

    do {
      let url = try await host.start()
      try await connection.connect(to: url)
      let service = CodexThreadService(connection: connection)

      if smoke {
        let workspace = try await service.refreshWorkspace(limit: 25)
        let sampler = MacTelemetrySampler()
        _ = await sampler.sample()
        try? await Task.sleep(for: .milliseconds(150))
        let metrics = await sampler.sample()
        let report = SmokeReport(
          appServerURL: url.absoluteString,
          projectCount: workspace.projects.count,
          threadCount: workspace.projects.flatMap(\.threads).count,
          liveThreadCount: workspace.projects.flatMap(\.threads).filter {
            $0.controlLevel == .live
          }.count,
          telemetry: metrics
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
        await connection.disconnect()
        await host.stop()
        return
      }

      let registry = SecureTransportRegistry()
      let transport = CompositeBridgeServer([
        NearbyServer(),
        WiFiServer(registry: registry),
      ])
      let coordinator = BridgeCoordinator(
        transport: transport,
        service: service,
        transportRegistry: registry,
        statusHandler: { message in
          FileHandle.standardOutput.write(Data("\(message)\n".utf8))
        }
      )
      await coordinator.start()
      let code = await coordinator.pairingCode
      let expiration = await coordinator.pairingExpiration
      print("\nEng Bridge is ready")
      print("Pairing code: \(code)")
      print("Code expires: \(expiration.formatted(date: .omitted, time: .shortened))")
      print("Connected Codex CLI command:")
      print("  ./Scripts/codex-eng")
      print("Press Control-C to stop.\n")

      await waitForTerminationSignal()
      await coordinator.stop()
      await connection.disconnect()
      await host.stop()
    } catch {
      FileHandle.standardError.write(
        Data("Eng Bridge failed: \(error.localizedDescription)\n".utf8))
      await connection.disconnect()
      await host.stop()
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func parsePort(_ arguments: ArraySlice<String>) -> UInt16? {
    guard let index = arguments.firstIndex(of: "--port"),
      index < arguments.index(before: arguments.endIndex),
      let value = UInt16(arguments[arguments.index(after: index)])
    else { return nil }
    return value
  }

  private static func waitForTerminationSignal() async {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let stream = AsyncStream<Void>.makeStream()
    let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    interruptSource.setEventHandler { stream.continuation.yield() }
    terminateSource.setEventHandler { stream.continuation.yield() }
    interruptSource.resume()
    terminateSource.resume()
    for await _ in stream.stream { break }
    interruptSource.cancel()
    terminateSource.cancel()
    stream.continuation.finish()
  }
}

private struct SmokeReport: Codable {
  let appServerURL: String
  let projectCount: Int
  let threadCount: Int
  let liveThreadCount: Int
  let telemetry: DeviceTelemetry
}
