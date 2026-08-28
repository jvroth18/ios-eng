import Charts
import EngCore
import SwiftUI

enum MetricFormatters {
  static func percent(_ value: Double?, fractionDigits: Int = 0) -> String {
    guard let value else { return "—" }
    return value.formatted(
      .number.precision(.fractionLength(fractionDigits)).rounded(rule: .toNearestOrAwayFromZero))
      + "%"
  }

  static func fractionPercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return percent(value * 100)
  }

  static func bytes(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
  }

  static func speed(_ value: Double?) -> String {
    guard let value else { return "—" }
    let bytes = ByteCountFormatter.string(
      fromByteCount: Int64(max(value, 0)),
      countStyle: .decimal
    )
    return "\(bytes)/s"
  }

  static func latency(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(value.formatted(.number.precision(.fractionLength(0)))) ms"
  }

  static func duration(_ value: TimeInterval) -> String {
    let days = Int(value / 86_400)
    let hours = Int(value.truncatingRemainder(dividingBy: 86_400) / 3_600)
    if days > 0 { return "\(days)d \(hours)h" }
    let minutes = Int(value / 60)
    return minutes >= 60 ? "\(hours)h" : "\(minutes)m"
  }
}

struct AnalyticsView: View {
  @EnvironmentObject private var store: BridgeStore

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        linkBox

        if let phone = store.analytics.phone {
          DeviceBox(telemetry: phone, history: store.phoneHistory)
        }

        if let mac = store.analytics.mac {
          DeviceBox(telemetry: mac, history: store.macHistory)
        } else {
          unavailableMacBox
        }

        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "info.circle")
            .font(.system(size: 12))
          Text(
            "Apple exposes thermal pressure, not exact device temperature, to normal iPhone apps. "
              + "Eng reports the public nominal/fair/serious/critical state and does not invent degrees."
          )
          .font(Win95Font.small)
          .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Win95.text)
        .padding(.horizontal, 4)
      }
      .padding(.vertical, 4)
    }
    .scrollIndicators(.hidden)
    .refreshable { store.refresh() }
  }

  private var linkBox: some View {
    Win95GroupBox(title: "Bridge link") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Win95Readout(
            value: MetricFormatters.latency(store.analytics.link.roundTripMilliseconds),
            label: "Round trip"
          )
          Win95Readout(
            value: MetricFormatters.speed(store.analytics.link.measuredBytesPerSecond),
            label: "Payload goodput"
          )
        }

        HStack(spacing: 8) {
          Win95LED(color: linkColor, blinking: store.analytics.link.quality == .unavailable)
          Text(store.analytics.link.quality.rawValue.capitalized)
            .font(Win95Font.bold)
          Spacer()
          Text(linkNote)
            .font(Win95Font.small)
        }
        .foregroundStyle(Win95.text)

        HStack(alignment: .top, spacing: 8) {
          Image(systemName: transportSymbol)
            .font(.system(size: 12))
            .frame(width: 16)
          VStack(alignment: .leading, spacing: 2) {
            Text(store.analytics.link.transport.title)
              .font(Win95Font.bold)
            Text(store.analytics.link.transport.detail)
              .font(Win95Font.small)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .foregroundStyle(Win95.text)

        Text("Sampled \(store.analytics.link.sampledAt.formatted(date: .omitted, time: .standard))")
          .font(Win95Font.small)
          .foregroundStyle(Win95.shadow)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var unavailableMacBox: some View {
    Win95GroupBox(title: "MacBook") {
      HStack(spacing: 10) {
        Image(systemName: "hourglass")
          .font(.system(size: 22))
        VStack(alignment: .leading, spacing: 3) {
          Text("Waiting for Mac diagnostics")
            .font(Win95Font.bold)
          Text("Keep Eng Bridge running and paired. The next telemetry sample will appear here.")
            .font(Win95Font.small)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .foregroundStyle(Win95.text)
      .padding(.vertical, 6)
    }
  }

  private var linkColor: Color {
    switch store.analytics.link.quality {
    case .excellent, .good: Win95.ledGreen
    case .constrained: Win95.ledYellow
    case .poor: Win95.ledRed
    case .unavailable: Win95.ledOff
    }
  }

  private var linkNote: String {
    if store.analytics.link.isConstrained == true { return "Low Data Mode" }
    if store.analytics.link.isExpensive == true { return "Metered" }
    return store.analytics.phone?.interface.rawValue.uppercased() ?? "—"
  }

  private var transportSymbol: String {
    switch store.analytics.link.transport {
    case .nearbyAuto: "dot.radiowaves.left.and.right"
    case .wifiDirect: "wifi"
    case .sshTunnel: "lock.fill"
    }
  }
}

private struct DeviceBox: View {
  let telemetry: DeviceTelemetry
  let history: [AnalyticsPoint]

  var body: some View {
    Win95GroupBox(title: telemetry.kind == .phone ? "iPhone" : "MacBook") {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: telemetry.kind == .phone ? "iphone" : "laptopcomputer")
            .font(.system(size: 14))
          Text(telemetry.name)
            .font(Win95Font.bold)
          Spacer()
          Text(telemetry.sampledAt.formatted(date: .omitted, time: .standard))
            .font(Win95Font.monoSmall)
        }
        .foregroundStyle(Win95.text)

        Win95MetricRow(
          label: "CPU",
          value: MetricFormatters.percent(telemetry.cpuUsagePercent),
          fraction: telemetry.cpuUsagePercent.map { $0 / 100 },
          detail: "\(telemetry.logicalCoreCount) logical cores"
        )
        Win95MetricRow(
          label: "Memory",
          value: MetricFormatters.bytes(telemetry.memoryUsedBytes),
          fraction: memoryFraction,
          detail: "of \(MetricFormatters.bytes(telemetry.memoryTotalBytes))"
        )
        Win95MetricRow(
          label: "Disk used",
          value: MetricFormatters.bytes(diskUsed),
          fraction: diskFraction,
          detail: "\(MetricFormatters.bytes(telemetry.diskFreeBytes)) free"
        )
        Win95MetricRow(
          label: "Battery",
          value: MetricFormatters.fractionPercent(telemetry.batteryLevel),
          fraction: telemetry.batteryLevel,
          detail: powerDetail
        )

        HStack(spacing: 10) {
          Win95MetricRow(
            label: "Thermal", value: telemetry.thermalLevel.rawValue.capitalized,
            detail: thermalDetail)
          Win95MetricRow(
            label: "Uptime", value: MetricFormatters.duration(telemetry.uptimeSeconds),
            detail: "App RAM \(MetricFormatters.bytes(telemetry.appResidentMemoryBytes))")
        }

        HStack(spacing: 8) {
          Image(systemName: interfaceSymbol)
            .font(.system(size: 12))
            .frame(width: 16)
          Text(telemetry.interface.rawValue.capitalized)
            .font(Win95Font.body)
          Spacer()
          Label(MetricFormatters.speed(telemetry.downloadBytesPerSecond), systemImage: "arrow.down")
          Label(MetricFormatters.speed(telemetry.uploadBytesPerSecond), systemImage: "arrow.up")
        }
        .font(Win95Font.mono)
        .foregroundStyle(Win95.text)
        .padding(6)
        .bevel(.status)

        if history.count > 2 {
          MonitorChart(history: history)
        }
      }
    }
  }

  private var memoryFraction: Double? {
    guard let used = telemetry.memoryUsedBytes, let total = telemetry.memoryTotalBytes, total > 0
    else { return nil }
    return Double(used) / Double(total)
  }

  private var diskUsed: UInt64? {
    guard let free = telemetry.diskFreeBytes, let total = telemetry.diskTotalBytes, total >= free
    else { return nil }
    return total - free
  }

  private var diskFraction: Double? {
    guard let used = diskUsed, let total = telemetry.diskTotalBytes, total > 0 else { return nil }
    return Double(used) / Double(total)
  }

  private var thermalDetail: String {
    switch telemetry.thermalLevel {
    case .nominal: "No pressure"
    case .fair: "Light pressure"
    case .serious: "Performance affected"
    case .critical: "Heavy throttling likely"
    case .unavailable: "Not exposed"
    }
  }

  private var powerDetail: String {
    if telemetry.lowPowerMode == true { return "Low Power Mode" }
    return telemetry.powerState.rawValue.capitalized
  }

  private var interfaceSymbol: String {
    switch telemetry.interface {
    case .wifi: "wifi"
    case .cellular: "antenna.radiowaves.left.and.right"
    case .wired: "cable.connector"
    case .loopback: "arrow.triangle.2.circlepath"
    case .other: "network"
    case .unavailable: "wifi.slash"
    }
  }
}

/// Task Manager-style CPU history: green stepped trace on black with a green grid.
private struct MonitorChart: View {
  let history: [AnalyticsPoint]

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("CPU Usage History")
        .font(Win95Font.small)
        .foregroundStyle(Win95.text)
      Chart(history) { point in
        if let cpu = point.cpuPercent {
          LineMark(
            x: .value("Time", point.sampledAt),
            y: .value("CPU", cpu)
          )
          .foregroundStyle(Win95.monitorTrace)
          .lineStyle(StrokeStyle(lineWidth: 1))
          .interpolationMethod(.stepEnd)
        }
      }
      .chartYScale(domain: 0...100)
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 8)) { _ in
          AxisGridLine().foregroundStyle(Win95.monitorGrid)
        }
      }
      .chartYAxis {
        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
          AxisGridLine().foregroundStyle(Win95.monitorGrid)
          AxisValueLabel {
            if let number = value.as(Int.self) {
              Text("\(number)%")
                .font(Win95Font.monoSmall)
                .foregroundStyle(Win95.monitorTrace)
            }
          }
        }
      }
      .chartPlotStyle { plot in
        plot.background(Win95.monitorBackground)
      }
      .padding(.top, 10)
      .padding([.horizontal, .bottom], 4)
      .frame(height: 120)
      .bevel(.sunken, fill: Win95.monitorBackground)
    }
  }
}
