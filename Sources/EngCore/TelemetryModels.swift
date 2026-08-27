import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Equatable, Sendable {
  case phone
  case mac
}

public enum ThermalLevel: String, Codable, CaseIterable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical
  case unavailable
}

public enum PowerState: String, Codable, CaseIterable, Equatable, Sendable {
  case charging
  case full
  case unplugged
  case unavailable
}

public enum NetworkInterfaceKind: String, Codable, CaseIterable, Equatable, Sendable {
  case wifi
  case cellular
  case wired
  case loopback
  case other
  case unavailable
}

public enum ConnectionQuality: String, Codable, CaseIterable, Equatable, Sendable {
  case excellent
  case good
  case constrained
  case poor
  case unavailable
}

public struct DeviceTelemetry: Codable, Equatable, Sendable, Identifiable {
  public var id: DeviceKind { kind }

  public let kind: DeviceKind
  public let name: String
  public let sampledAt: Date
  public let cpuUsagePercent: Double?
  public let logicalCoreCount: Int
  public let memoryUsedBytes: UInt64?
  public let memoryTotalBytes: UInt64?
  public let appResidentMemoryBytes: UInt64?
  public let diskFreeBytes: UInt64?
  public let diskTotalBytes: UInt64?
  public let batteryLevel: Double?
  public let powerState: PowerState
  public let lowPowerMode: Bool?
  public let thermalLevel: ThermalLevel
  public let uptimeSeconds: TimeInterval
  public let interface: NetworkInterfaceKind
  public let downloadBytesPerSecond: Double?
  public let uploadBytesPerSecond: Double?

  public init(
    kind: DeviceKind,
    name: String,
    sampledAt: Date = Date(),
    cpuUsagePercent: Double? = nil,
    logicalCoreCount: Int,
    memoryUsedBytes: UInt64? = nil,
    memoryTotalBytes: UInt64? = nil,
    appResidentMemoryBytes: UInt64? = nil,
    diskFreeBytes: UInt64? = nil,
    diskTotalBytes: UInt64? = nil,
    batteryLevel: Double? = nil,
    powerState: PowerState = .unavailable,
    lowPowerMode: Bool? = nil,
    thermalLevel: ThermalLevel,
    uptimeSeconds: TimeInterval,
    interface: NetworkInterfaceKind = .unavailable,
    downloadBytesPerSecond: Double? = nil,
    uploadBytesPerSecond: Double? = nil
  ) {
    self.kind = kind
    self.name = name
    self.sampledAt = sampledAt
    self.cpuUsagePercent = cpuUsagePercent
    self.logicalCoreCount = logicalCoreCount
    self.memoryUsedBytes = memoryUsedBytes
    self.memoryTotalBytes = memoryTotalBytes
    self.appResidentMemoryBytes = appResidentMemoryBytes
    self.diskFreeBytes = diskFreeBytes
    self.diskTotalBytes = diskTotalBytes
    self.batteryLevel = batteryLevel
    self.powerState = powerState
    self.lowPowerMode = lowPowerMode
    self.thermalLevel = thermalLevel
    self.uptimeSeconds = uptimeSeconds
    self.interface = interface
    self.downloadBytesPerSecond = downloadBytesPerSecond
    self.uploadBytesPerSecond = uploadBytesPerSecond
  }
}

public struct LinkTelemetry: Codable, Equatable, Sendable {
  public let sampledAt: Date
  public let roundTripMilliseconds: Double?
  public let measuredBytesPerSecond: Double?
  public let quality: ConnectionQuality
  public let isExpensive: Bool?
  public let isConstrained: Bool?

  public init(
    sampledAt: Date = Date(),
    roundTripMilliseconds: Double? = nil,
    measuredBytesPerSecond: Double? = nil,
    quality: ConnectionQuality = .unavailable,
    isExpensive: Bool? = nil,
    isConstrained: Bool? = nil
  ) {
    self.sampledAt = sampledAt
    self.roundTripMilliseconds = roundTripMilliseconds
    self.measuredBytesPerSecond = measuredBytesPerSecond
    self.quality = quality
    self.isExpensive = isExpensive
    self.isConstrained = isConstrained
  }
}

public struct AnalyticsSnapshot: Codable, Equatable, Sendable {
  public let phone: DeviceTelemetry?
  public let mac: DeviceTelemetry?
  public let link: LinkTelemetry

  public init(phone: DeviceTelemetry?, mac: DeviceTelemetry?, link: LinkTelemetry) {
    self.phone = phone
    self.mac = mac
    self.link = link
  }
}

public enum TelemetryAnalysis {
  public static func connectionQuality(
    roundTripMilliseconds: Double?,
    measuredBytesPerSecond: Double?,
    constrained: Bool = false
  ) -> ConnectionQuality {
    guard let latency = roundTripMilliseconds, let throughput = measuredBytesPerSecond else {
      return .unavailable
    }
    if constrained { return .constrained }
    if latency < 50, throughput >= 5_000_000 { return .excellent }
    if latency < 150, throughput >= 1_000_000 { return .good }
    if latency < 400, throughput >= 100_000 { return .constrained }
    return .poor
  }
}
