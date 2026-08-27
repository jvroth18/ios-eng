import EngBridgeCore
import EngCore
import Testing

struct MacTelemetrySamplerTests {
  @Test func samplesPublicMacDiagnostics() async throws {
    let sampler = MacTelemetrySampler()
    _ = await sampler.sample()
    try await Task.sleep(for: .milliseconds(100))
    let sample = await sampler.sample()

    #expect(sample.kind == .mac)
    #expect(sample.logicalCoreCount > 0)
    #expect((sample.memoryTotalBytes ?? 0) > 0)
    #expect((sample.diskTotalBytes ?? 0) > 0)
    #expect(sample.uptimeSeconds > 0)
    if let cpu = sample.cpuUsagePercent {
      #expect((0...100).contains(cpu))
    }
    if let download = sample.downloadBytesPerSecond {
      #expect(download >= 0)
    }
  }
}
