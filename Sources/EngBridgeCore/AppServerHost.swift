import Foundation

public actor AppServerHost {
  public let port: UInt16
  public var webSocketURL: URL {
    URL(string: "ws://127.0.0.1:\(port)")!
  }

  private var process: Process?
  private var ownsProcess = false

  public init(port: UInt16 = 47_321) {
    self.port = port
  }

  public func start() async throws -> URL {
    if await isReady() {
      ownsProcess = false
      return webSocketURL
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "codex", "app-server", "--listen", "ws://127.0.0.1:\(port)",
    ]
    process.standardOutput = FileHandle.standardError
    process.standardError = FileHandle.standardError
    try process.run()
    self.process = process
    ownsProcess = true

    for _ in 0..<80 {
      if await isReady() { return webSocketURL }
      if !process.isRunning {
        throw AppServerFailure(
          code: Int(process.terminationStatus),
          message: "Codex App Server exited before becoming ready"
        )
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    await stop()
    throw AppServerFailure(message: "Timed out waiting for Codex App Server readiness")
  }

  public func stop() async {
    guard ownsProcess, let process else { return }
    if process.isRunning { process.terminate() }
    for _ in 0..<20 where process.isRunning {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if process.isRunning { process.interrupt() }
    self.process = nil
    ownsProcess = false
  }

  private func isReady() async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/readyz") else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 0.4
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }
}
