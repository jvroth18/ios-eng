import EngCore
import Foundation
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

  @Test func activityMirrorsTheCurrentCodexOperation() {
    let thread = ThreadSummary(
      id: "t1", title: "Thread", preview: "", cwd: "/tmp", repositoryRoot: "/tmp",
      source: "cli", status: .active, controlLevel: .live, activeTurnID: "turn-1",
      updatedAt: Date())
    let command = TimelineItem(
      id: "command-1", threadID: "t1", turnID: "turn-1", kind: .command,
      state: .running, title: "swift test", body: "", timestamp: Date())

    let running = ThreadActivityPresentation.current(
      thread: thread, timeline: [command], pendingActions: [], isSending: false)
    #expect(running?.title == "Running command")
    #expect(running?.detail == "swift test")
    #expect(running?.isActive == true)

    let thinking = ThreadActivityPresentation.current(
      thread: thread, timeline: [], pendingActions: [], isSending: true)
    #expect(thinking?.title == "Thinking")
  }
}
