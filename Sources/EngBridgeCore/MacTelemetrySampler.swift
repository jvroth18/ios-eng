import Darwin
import EngCore
import Foundation
import IOKit.ps
import Network

public actor MacTelemetrySampler {
  private struct CPUTicks: Sendable {
    let used: UInt64
    let total: UInt64
  }

  private struct NetworkTotals: Sendable {
    let received: UInt64
    let sent: UInt64
    let sampledAt: Date
  }

  private let pathObserver = NetworkPathObserver()
  private var previousCPU: CPUTicks?
  private var previousNetwork: NetworkTotals?

  public init() {}

  public func sample(now: Date = Date()) -> DeviceTelemetry {
    let cpuTicks = readCPUTicks()
    let cpuUsage = calculateCPUUsage(current: cpuTicks, previous: previousCPU)
    previousCPU = cpuTicks

    let networkTotals = readNetworkTotals(at: now)
    let rates = calculateNetworkRates(current: networkTotals, previous: previousNetwork)
    previousNetwork = networkTotals

    let disk = readDisk()
    let battery = readBattery()
    let processInfo = ProcessInfo.processInfo

    return DeviceTelemetry(
      kind: .mac,
      name: Host.current().localizedName ?? "Mac",
      sampledAt: now,
      cpuUsagePercent: cpuUsage,
      logicalCoreCount: processInfo.activeProcessorCount,
      memoryUsedBytes: readUsedMemory(total: processInfo.physicalMemory),
      memoryTotalBytes: processInfo.physicalMemory,
      appResidentMemoryBytes: readResidentMemory(),
      diskFreeBytes: disk.free,
      diskTotalBytes: disk.total,
      batteryLevel: battery.level,
      powerState: battery.state,
      lowPowerMode: processInfo.isLowPowerModeEnabled,
      thermalLevel: Self.thermalLevel(processInfo.thermalState),
      uptimeSeconds: processInfo.systemUptime,
      interface: pathObserver.interfaceKind,
      downloadBytesPerSecond: rates.received,
      uploadBytesPerSecond: rates.sent
    )
  }

  private func readCPUTicks() -> CPUTicks? {
    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let user = UInt64(info.cpu_ticks.0)
    let system = UInt64(info.cpu_ticks.1)
    let idle = UInt64(info.cpu_ticks.2)
    let nice = UInt64(info.cpu_ticks.3)
    return CPUTicks(used: user + system + nice, total: user + system + idle + nice)
  }

  private func calculateCPUUsage(current: CPUTicks?, previous: CPUTicks?) -> Double? {
    guard let current, let previous,
      current.total > previous.total,
      current.used >= previous.used
    else { return nil }
    let used = Double(current.used - previous.used)
    let total = Double(current.total - previous.total)
    return min(max((used / total) * 100, 0), 100)
  }

  private func readUsedMemory(total: UInt64) -> UInt64? {
    var pageSize: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
    var info = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let free = UInt64(info.free_count + info.speculative_count) * UInt64(pageSize)
    return total >= free ? total - free : nil
  }

  private func readResidentMemory() -> UInt64? {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
      }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
  }

  private func readDisk() -> (free: UInt64?, total: UInt64?) {
    do {
      let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeTotalCapacityKey,
      ])
      let free = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) }
      let total = values.volumeTotalCapacity.map { UInt64(max($0, 0)) }
      return (free, total)
    } catch {
      return (nil, nil)
    }
  }

  private func readBattery() -> (level: Double?, state: PowerState) {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
    else { return (nil, .unavailable) }

    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
          as? [String: Any]
      else { continue }
      let current = description[kIOPSCurrentCapacityKey as String] as? Double
      let maximum = description[kIOPSMaxCapacityKey as String] as? Double
      let level = current.flatMap { current in
        maximum.flatMap { $0 > 0 ? min(max(current / $0, 0), 1) : nil }
      }
      let isCharging = description[kIOPSIsChargingKey as String] as? Bool == true
      let sourceState = description[kIOPSPowerSourceStateKey as String] as? String
      let state: PowerState
      if isCharging {
        state = .charging
      } else if level == 1 {
        state = .full
      } else if sourceState == kIOPSBatteryPowerValue {
        state = .unplugged
      } else {
        state = .full
      }
      return (level, state)
    }
    return (nil, .unavailable)
  }

  private func readNetworkTotals(at date: Date) -> NetworkTotals? {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
    defer { freeifaddrs(firstAddress) }

    var received: UInt64 = 0
    var sent: UInt64 = 0
    var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
    while let current = pointer {
      let address = current.pointee
      if address.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
        (address.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
        (address.ifa_flags & UInt32(IFF_UP)) != 0,
        let raw = address.ifa_data
      {
        let data = raw.assumingMemoryBound(to: if_data.self).pointee
        received &+= UInt64(data.ifi_ibytes)
        sent &+= UInt64(data.ifi_obytes)
      }
      pointer = address.ifa_next
    }
    return NetworkTotals(received: received, sent: sent, sampledAt: date)
  }

  private func calculateNetworkRates(
    current: NetworkTotals?,
    previous: NetworkTotals?
  ) -> (received: Double?, sent: Double?) {
    guard let current, let previous else { return (nil, nil) }
    let duration = current.sampledAt.timeIntervalSince(previous.sampledAt)
    guard duration > 0,
      current.received >= previous.received,
      current.sent >= previous.sent
    else { return (nil, nil) }
    return (
      Double(current.received - previous.received) / duration,
      Double(current.sent - previous.sent) / duration
    )
  }

  private static func thermalLevel(_ value: ProcessInfo.ThermalState) -> ThermalLevel {
    switch value {
    case .nominal: .nominal
    case .fair: .fair
    case .serious: .serious
    case .critical: .critical
    @unknown default: .unavailable
    }
  }
}

private final class NetworkPathObserver: @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let lock = NSLock()
  private var currentInterface: NetworkInterfaceKind = .unavailable

  var interfaceKind: NetworkInterfaceKind {
    lock.withLock { currentInterface }
  }

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let kind: NetworkInterfaceKind
      if path.usesInterfaceType(.wifi) {
        kind = .wifi
      } else if path.usesInterfaceType(.wiredEthernet) {
        kind = .wired
      } else if path.usesInterfaceType(.cellular) {
        kind = .cellular
      } else if path.usesInterfaceType(.loopback) {
        kind = .loopback
      } else {
        kind = path.status == .satisfied ? .other : .unavailable
      }
      self?.lock.withLock { self?.currentInterface = kind }
    }
    monitor.start(queue: DispatchQueue(label: "dev.jvroth.ios-eng.network-path"))
  }

  deinit {
    monitor.cancel()
  }
}
