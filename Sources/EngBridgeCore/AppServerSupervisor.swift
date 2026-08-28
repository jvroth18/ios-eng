import Foundation

public enum AppServerSupervisorState: Equatable, Sendable {
  case connecting
  case connected
  case recovering(attempt: Int, message: String)
  case stopped
}

public actor AppServerSupervisor {
  public nonisolated let states: AsyncStream<AppServerSupervisorState>

  private let stateContinuation: AsyncStream<AppServerSupervisorState>.Continuation
  private let ensureHost: @Sendable () async throws -> URL
  private let hostReady: @Sendable () async -> Bool
  private let connectionReady: @Sendable () async -> Bool
  private let connect: @Sendable (URL) async throws -> Void
  private let disconnect: @Sendable () async -> Void
  private let pollInterval: Duration
  private var monitorTask: Task<Void, Never>?
  private var currentState = AppServerSupervisorState.stopped

  public init(
    host: AppServerHost,
    connection: AppServerConnection,
    pollInterval: Duration = .seconds(1)
  ) {
    let stream = AsyncStream<AppServerSupervisorState>.makeStream()
    states = stream.stream
    stateContinuation = stream.continuation
    ensureHost = { try await host.start() }
    hostReady = { await host.isReady() }
    connectionReady = { await connection.isConnected }
    connect = { try await connection.connect(to: $0) }
    disconnect = { await connection.disconnect() }
    self.pollInterval = pollInterval
  }

  init(
    pollInterval: Duration,
    ensureHost: @escaping @Sendable () async throws -> URL,
    hostReady: @escaping @Sendable () async -> Bool,
    connectionReady: @escaping @Sendable () async -> Bool,
    connect: @escaping @Sendable (URL) async throws -> Void,
    disconnect: @escaping @Sendable () async -> Void
  ) {
    let stream = AsyncStream<AppServerSupervisorState>.makeStream()
    states = stream.stream
    stateContinuation = stream.continuation
    self.ensureHost = ensureHost
    self.hostReady = hostReady
    self.connectionReady = connectionReady
    self.connect = connect
    self.disconnect = disconnect
    self.pollInterval = pollInterval
  }

  deinit { stateContinuation.finish() }

  public func start() async throws {
    guard monitorTask == nil else { return }
    transition(to: .connecting)
    try await recover()
    monitorTask = Task { [weak self] in
      await self?.monitor()
    }
  }

  public func stop() async {
    monitorTask?.cancel()
    monitorTask = nil
    await disconnect()
    transition(to: .stopped)
  }

  private func monitor() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: pollInterval)
      guard !Task.isCancelled else { return }
      if await hostReady(), await connectionReady() { continue }
      await disconnect()
      transition(to: .connecting)
      var attempt = 0
      while !Task.isCancelled {
        attempt += 1
        do {
          try await recover()
          break
        } catch {
          transition(to: .recovering(attempt: attempt, message: error.localizedDescription))
          let milliseconds = min(250 * (1 << min(attempt - 1, 4)), 4_000)
          try? await Task.sleep(for: .milliseconds(milliseconds))
        }
      }
    }
  }

  private func recover() async throws {
    let url = try await ensureHost()
    try await connect(url)
    transition(to: .connected)
  }

  private func transition(to state: AppServerSupervisorState) {
    guard state != currentState else { return }
    currentState = state
    stateContinuation.yield(state)
  }
}
