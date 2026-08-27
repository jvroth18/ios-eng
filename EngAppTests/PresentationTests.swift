import Testing

@testable import Eng

struct PresentationTests {
  @Test func metricFormattersMakeMissingAndMeasuredValuesReadable() {
    #expect(MetricFormatters.percent(nil) == "—")
    #expect(MetricFormatters.percent(42.4) == "42%")
    #expect(MetricFormatters.fractionPercent(0.73) == "73%")
    #expect(MetricFormatters.latency(18.6) == "19 ms")
    #expect(MetricFormatters.duration(90_000) == "1d 1h")
  }

  @Test func analyticsPointCalculatesBoundedMemoryFraction() throws {
    let telemetry = DeviceTelemetry(
      kind: .phone,
      name: "iPhone",
      cpuUsagePercent: 22,
      logicalCoreCount: 6,
      memoryUsedBytes: 4_000,
      memoryTotalBytes: 8_000,
      thermalLevel: .nominal,
      uptimeSeconds: 60
    )
    let point = AnalyticsPoint(telemetry)
    #expect(point.cpuPercent == 22)
    #expect(point.memoryFraction == 0.5)
  }
}
