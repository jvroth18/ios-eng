import Charts
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
    NavigationStack {
      ZStack {
        EngCanvas()
        ScrollView {
          LazyVStack(spacing: 18) {
            linkCard

            if let phone = store.analytics.phone {
              DeviceAnalyticsCard(
                telemetry: phone,
                history: store.phoneHistory,
                cpuLabel: "System CPU"
              )
            }

            if let mac = store.analytics.mac {
              DeviceAnalyticsCard(
                telemetry: mac,
                history: store.macHistory,
                cpuLabel: "System CPU"
              )
            } else {
              unavailableMacCard
            }

            thermalNote
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 30)
        }
        .refreshable { store.refresh() }
      }
      .navigationTitle("Analytics")
      .navigationBarTitleDisplayMode(.large)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { ConnectionPill() }
      }
    }
  }

  private var linkCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      EngSectionHeader(
        eyebrow: "Live link",
        title: "Phone ↔ Mac",
        trailing: store.analytics.link.sampledAt.formatted(date: .omitted, time: .standard)
      )

      HStack(spacing: 12) {
        LinkHeroMetric(
          value: MetricFormatters.latency(store.analytics.link.roundTripMilliseconds),
          label: "Round trip",
          symbol: "arrow.left.arrow.right"
        )
        LinkHeroMetric(
          value: MetricFormatters.speed(store.analytics.link.measuredBytesPerSecond),
          label: "Payload goodput",
          symbol: "gauge.with.dots.needle.67percent"
        )
      }

      HStack(alignment: .top, spacing: 10) {
        Image(systemName: transportSymbol)
          .foregroundStyle(EngDesign.cyan)
        VStack(alignment: .leading, spacing: 3) {
          Text(store.analytics.link.transport.title)
            .font(.subheadline.weight(.semibold))
          Text(store.analytics.link.transport.detail)
            .font(.caption)
            .foregroundStyle(EngDesign.muted)
            .lineSpacing(2)
        }
      }

      HStack {
        StatusDot(color: linkColor, pulsing: store.analytics.link.quality == .excellent)
        Text(store.analytics.link.quality.rawValue.capitalized)
          .font(.subheadline.weight(.semibold))
        Spacer()
        if store.analytics.link.isConstrained == true {
          Label("Low Data Mode", systemImage: "tortoise.fill")
        } else if store.analytics.link.isExpensive == true {
          Label("Metered", systemImage: "antenna.radiowaves.left.and.right")
        } else {
          Label(store.analytics.phone?.interface.rawValue.uppercased() ?? "—", systemImage: "wifi")
        }
      }
      .font(.caption)
      .foregroundStyle(EngDesign.muted)
    }
    .glassCard()
  }

  private var unavailableMacCard: some View {
    VStack(spacing: 12) {
      Image(systemName: "macbook.slash")
        .font(.title)
        .foregroundStyle(EngDesign.muted)
      Text("Waiting for Mac diagnostics")
        .font(.headline)
      Text("Keep Eng Bridge running and paired. The next telemetry sample will appear here.")
        .font(.caption)
        .foregroundStyle(EngDesign.muted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
    .glassCard()
  }

  private var thermalNote: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "thermometer.medium")
        .foregroundStyle(EngDesign.amber)
      Text(
        "Apple exposes thermal pressure—not exact device temperature—to normal iPhone apps. Eng reports the public nominal, fair, serious, or critical state and does not invent degrees."
      )
      .font(.caption)
      .foregroundStyle(EngDesign.muted)
      .lineSpacing(3)
    }
    .padding(.horizontal, 5)
  }

  private var linkColor: Color {
    switch store.analytics.link.quality {
    case .excellent: EngDesign.mint
    case .good: EngDesign.cyan
    case .constrained: EngDesign.amber
    case .poor: EngDesign.coral
    case .unavailable: EngDesign.muted
    }
  }

  private var transportSymbol: String {
    switch store.analytics.link.transport {
    case .nearbyAuto: "dot.radiowaves.left.and.right"
    case .wifiDirect: "wifi"
    case .sshTunnel: "lock.shield.fill"
    }
  }
}

private struct LinkHeroMetric: View {
  let value: String
  let label: String
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(EngDesign.accent)
      Text(value)
        .font(.title3.weight(.bold).monospacedDigit())
        .minimumScaleFactor(0.72)
        .lineLimit(1)
      Text(label)
        .font(.caption2)
        .foregroundStyle(EngDesign.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 17))
  }
}

private struct DeviceAnalyticsCard: View {
  let telemetry: DeviceTelemetry
  let history: [AnalyticsPoint]
  let cpuLabel: String

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      EngSectionHeader(
        eyebrow: telemetry.kind == .phone ? "iPhone" : "MacBook",
        title: telemetry.name,
        trailing: telemetry.sampledAt.formatted(date: .omitted, time: .standard)
      )

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        MetricTile(
          symbol: "cpu",
          title: cpuLabel,
          value: MetricFormatters.percent(telemetry.cpuUsagePercent),
          detail: "\(telemetry.logicalCoreCount) logical cores",
          tint: EngDesign.cyan
        )
        MetricTile(
          symbol: "thermometer.medium",
          title: "Thermal state",
          value: telemetry.thermalLevel.rawValue.capitalized,
          detail: thermalDetail,
          tint: thermalColor
        )
        MetricTile(
          symbol: "memorychip",
          title: "Memory",
          value: MetricFormatters.bytes(telemetry.memoryUsedBytes),
          detail: "of \(MetricFormatters.bytes(telemetry.memoryTotalBytes))",
          tint: EngDesign.violet
        )
        MetricTile(
          symbol: "internaldrive",
          title: "Storage free",
          value: MetricFormatters.bytes(telemetry.diskFreeBytes),
          detail: "of \(MetricFormatters.bytes(telemetry.diskTotalBytes))",
          tint: EngDesign.mint
        )
        MetricTile(
          symbol: powerSymbol,
          title: "Battery",
          value: MetricFormatters.fractionPercent(telemetry.batteryLevel),
          detail: powerDetail,
          tint: telemetry.lowPowerMode == true ? EngDesign.amber : EngDesign.mint
        )
        MetricTile(
          symbol: "clock.arrow.circlepath",
          title: "Uptime",
          value: MetricFormatters.duration(telemetry.uptimeSeconds),
          detail: "App RAM \(MetricFormatters.bytes(telemetry.appResidentMemoryBytes))",
          tint: EngDesign.cyan
        )
      }

      NetworkRateStrip(telemetry: telemetry)

      if history.count > 2 {
        DeviceHistoryChart(history: history)
      }
    }
    .glassCard()
  }

  private var thermalColor: Color {
    switch telemetry.thermalLevel {
    case .nominal: EngDesign.mint
    case .fair: EngDesign.cyan
    case .serious: EngDesign.amber
    case .critical: EngDesign.coral
    case .unavailable: EngDesign.muted
    }
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

  private var powerSymbol: String {
    switch telemetry.powerState {
    case .charging: "battery.75percent.bolt"
    case .full: "battery.100percent"
    case .unplugged: "battery.50percent"
    case .unavailable: "battery.0percent"
    }
  }

  private var powerDetail: String {
    if telemetry.lowPowerMode == true { return "Low Power Mode" }
    return telemetry.powerState.rawValue.capitalized
  }
}

private struct MetricTile: View {
  let symbol: String
  let title: String
  let value: String
  let detail: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: symbol).foregroundStyle(tint)
        Spacer()
      }
      Text(value)
        .font(.headline.weight(.bold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(title)
        .font(.caption.weight(.semibold))
      Text(detail)
        .font(.caption2)
        .foregroundStyle(EngDesign.muted)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(13)
    .background(Color.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 17))
  }
}

private struct NetworkRateStrip: View {
  let telemetry: DeviceTelemetry

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: interfaceSymbol)
        .font(.title3)
        .foregroundStyle(EngDesign.cyan)
      VStack(alignment: .leading, spacing: 2) {
        Text(telemetry.interface.rawValue.capitalized)
          .font(.caption.weight(.semibold))
        Text("Live interface traffic")
          .font(.caption2)
          .foregroundStyle(EngDesign.muted)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Label(MetricFormatters.speed(telemetry.downloadBytesPerSecond), systemImage: "arrow.down")
        Label(MetricFormatters.speed(telemetry.uploadBytesPerSecond), systemImage: "arrow.up")
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(Color.white.opacity(0.78))
    }
    .padding(13)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
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

private struct DeviceHistoryChart: View {
  let history: [AnalyticsPoint]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("RECENT LOAD")
        .font(.caption2.weight(.bold))
        .tracking(1.4)
        .foregroundStyle(EngDesign.muted)
      Chart(history) { point in
        if let cpu = point.cpuPercent {
          LineMark(
            x: .value("Time", point.sampledAt),
            y: .value("CPU", cpu)
          )
          .foregroundStyle(EngDesign.cyan)
          .interpolationMethod(.catmullRom)
          AreaMark(
            x: .value("Time", point.sampledAt),
            y: .value("CPU", cpu)
          )
          .foregroundStyle(
            LinearGradient(
              colors: [EngDesign.cyan.opacity(0.28), .clear],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .interpolationMethod(.catmullRom)
        }
      }
      .chartYScale(domain: 0...100)
      .chartXAxis(.hidden)
      .chartYAxis {
        AxisMarks(values: [0, 50, 100]) { value in
          AxisGridLine().foregroundStyle(EngDesign.border)
          AxisValueLabel {
            if let number = value.as(Int.self) { Text("\(number)%") }
          }
          .foregroundStyle(EngDesign.muted)
        }
      }
      .frame(height: 128)
    }
  }
}
