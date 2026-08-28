import Darwin
import EngCore
import Foundation
import Network
import UIKit

struct PhoneTelemetrySample: Sendable {
  let telemetry: DeviceTelemetry
  let isExpensive: Bool
  let isConstrained: Bool
}

@MainActor
final class PhoneTelemetrySampler {
  private struct CPUTicks {
    let used: UInt64
    let total: UInt64
  }

  private struct NetworkTotals {
    let received: UInt64
    let sent: UInt64
    let sampledAt: Date
  }

  private let pathObserver = PhoneNetworkPathObserver()
  private var previousCPU: CPUTicks?
  private var previousNetwork: NetworkTotals?

  init() {
    UIDevice.current.isBatteryMonitoringEnabled = true
  }

  func sample(now: Date = Date()) -> PhoneTelemetrySample {
    let cpuTicks = readCPUTicks()
    let cpuUsage = calculateCPUUsage(current: cpuTicks, previous: previousCPU)
    previousCPU = cpuTicks

    let networkTotals = readNetworkTotals(at: now)
    let rates = calculateNetworkRates(current: networkTotals, previous: previousNetwork)
    previousNetwork = networkTotals

    let processInfo = ProcessInfo.processInfo
    let device = UIDevice.current
    let path = pathObserver.snapshot
    let disk = readDisk()
    let batteryLevel = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil

    let telemetry = DeviceTelemetry(
      kind: .phone,
      name: device.name,
      sampledAt: now,
      cpuUsagePercent: cpuUsage,
      logicalCoreCount: processInfo.activeProcessorCount,
      memoryUsedBytes: readUsedMemory(total: processInfo.physicalMemory),
      memoryTotalBytes: processInfo.physicalMemory,
      appResidentMemoryBytes: readResidentMemory(),
      diskFreeBytes: disk.free,
      diskTotalBytes: disk.total,
      batteryLevel: batteryLevel,
      powerState: Self.powerState(device.batteryState),
      lowPowerMode: processInfo.isLowPowerModeEnabled,
      thermalLevel: Self.thermalLevel(processInfo.thermalState),
      uptimeSeconds: processInfo.systemUptime,
      interface: path.interface,
      downloadBytesPerSecond: rates.received,
      uploadBytesPerSecond: rates.sent
    )
    return PhoneTelemetrySample(
      telemetry: telemetry,
      isExpensive: path.isExpensive,
      isConstrained: path.isConstrained
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
      MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
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
      let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
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

  private static func powerState(_ value: UIDevice.BatteryState) -> PowerState {
    switch value {
    case .charging: .charging
    case .full: .full
    case .unplugged: .unplugged
    case .unknown: .unavailable
    @unknown default: .unavailable
    }
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

private struct PhoneNetworkPathSnapshot: Sendable {
  let interface: NetworkInterfaceKind
  let isExpensive: Bool
  let isConstrained: Bool
}

private final class PhoneNetworkPathObserver: @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let lock = NSLock()
  private var current = PhoneNetworkPathSnapshot(
    interface: .unavailable,
    isExpensive: false,
    isConstrained: false
  )

  var snapshot: PhoneNetworkPathSnapshot { lock.withLock { current } }

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let interface: NetworkInterfaceKind
      if path.usesInterfaceType(.wifi) {
        interface = .wifi
      } else if path.usesInterfaceType(.cellular) {
        interface = .cellular
      } else if path.usesInterfaceType(.wiredEthernet) {
        interface = .wired
      } else if path.usesInterfaceType(.loopback) {
        interface = .loopback
      } else {
        interface = path.status == .satisfied ? .other : .unavailable
      }
      let snapshot = PhoneNetworkPathSnapshot(
        interface: interface,
        isExpensive: path.isExpensive,
        isConstrained: path.isConstrained
      )
      self?.lock.withLock { self?.current = snapshot }
    }
    monitor.start(queue: DispatchQueue(label: "dev.jvroth.eng.network-path"))
  }

  deinit {
    monitor.cancel()
  }
}
