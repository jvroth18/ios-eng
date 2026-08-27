import Testing

@testable import EngCore

struct TelemetryAnalysisTests {
  @Test(arguments: [
    (20.0, 8_000_000.0, false, ConnectionQuality.excellent),
    (90.0, 2_000_000.0, false, ConnectionQuality.good),
    (250.0, 400_000.0, false, ConnectionQuality.constrained),
    (700.0, 20_000.0, false, ConnectionQuality.poor),
    (20.0, 8_000_000.0, true, ConnectionQuality.constrained),
  ])
  func classifiesMeasuredLink(
    latency: Double,
    throughput: Double,
    constrained: Bool,
    expected: ConnectionQuality
  ) {
    #expect(
      TelemetryAnalysis.connectionQuality(
        roundTripMilliseconds: latency,
        measuredBytesPerSecond: throughput,
        constrained: constrained
      ) == expected
    )
  }

  @Test func missingMeasurementIsUnavailable() {
    #expect(
      TelemetryAnalysis.connectionQuality(
        roundTripMilliseconds: nil,
        measuredBytesPerSecond: 1_000_000
      ) == .unavailable
    )
  }
}
