import Foundation
import Testing

@testable import EngBridgeCore

struct AppServerSupervisorTests {
  @Test func reconnectsAfterHostAndSocketFailureWithBoundedRetry() async throws {
    let probe = RecoveryProbe()
    let supervisor = AppServerSupervisor(
      pollInterval: .milliseconds(10),
      ensureHost: { try await probe.ensureHost() },
      hostReady: { await probe.hostReady },
      connectionReady: { await probe.connectionReady },
      connect: { try await probe.connect($0) },
      disconnect: { await probe.disconnect() }
    )
    let recorder = StateRecorder()
    let recordingTask = Task { [states = supervisor.states] in
      for await state in states { await recorder.append(state) }
    }

    try await supervisor.start()
    await probe.failNextConnectionAndDropRuntime()

    for _ in 0..<100 {
      if await probe.connectionAttempts >= 3 { break }
      try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await probe.connectionAttempts >= 3)
    #expect(await probe.hostReady)
    #expect(await probe.connectionReady)
    let states = await recorder.values
    #expect(states.contains(.connected))
    #expect(
      states.contains {
        if case .recovering = $0 { return true }
        return false
      })

    await supervisor.stop()
    recordingTask.cancel()
  }
}

private actor RecoveryProbe {
  private(set) var hostReady = false
  private(set) var connectionReady = false
  private(set) var connectionAttempts = 0
  private var failuresRemaining = 0

  func ensureHost() throws -> URL {
    hostReady = true
    return URL(string: "ws://127.0.0.1:47321")!
  }

  func connect(_ url: URL) throws {
    connectionAttempts += 1
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw AppServerFailure(message: "Injected reconnect failure")
    }
    connectionReady = true
  }

  func disconnect() { connectionReady = false }

  func failNextConnectionAndDropRuntime() {
    failuresRemaining = 1
    hostReady = false
    connectionReady = false
  }
}

private actor StateRecorder {
  private(set) var values: [AppServerSupervisorState] = []

  func append(_ value: AppServerSupervisorState) { values.append(value) }
}
