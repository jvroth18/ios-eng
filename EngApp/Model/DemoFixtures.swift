import EngCore
import Foundation

#if DEBUG
  enum DemoFixtures {
    static let now = Date()

    static let liveThread = ThreadSummary(
      id: "demo-live",
      title: "Build native phone analytics",
      preview: "Build the Analytics view and validate it on device.",
      cwd: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
      repositoryRoot: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
      source: "vscode",
      status: .active,
      controlLevel: .live,
      activeTurnID: "turn-live",
      updatedAt: now.addingTimeInterval(-24)
    )

    static let workspace = WorkspaceSnapshot(
      bridgeName: "Jordan’s MacBook Pro",
      projects: [
        ProjectSummary(
          id: "ios-eng",
          name: "ios-eng",
          repositoryRoot: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
          gitOrigin: "git@github.com:jvroth18/ios-eng.git",
          threads: [
            liveThread,
            ThreadSummary(
              id: "demo-waiting",
              title: "Review transport safeguards",
              preview: "Approve the local test command.",
              cwd: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
              repositoryRoot: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
              source: "cli",
              status: .waiting,
              controlLevel: .live,
              activeTurnID: "turn-waiting",
              needsAttention: true,
              updatedAt: now.addingTimeInterval(-120)
            ),
            ThreadSummary(
              id: "demo-saved",
              title: "Sketch the App Server bridge",
              preview: "Architecture and product boundary are documented.",
              cwd: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
              repositoryRoot: "/Users/jordanrothstein/Desktop/Testing/ios-eng",
              source: "vscode",
              status: .notLoaded,
              controlLevel: .message,
              updatedAt: now.addingTimeInterval(-4_200)
            ),
          ],
          updatedAt: now
        ),
        ProjectSummary(
          id: "relay",
          name: "relay-web-app",
          repositoryRoot: "/Users/jordanrothstein/Desktop/GitHub/relay-web-app",
          gitOrigin: "git@github.com:jvroth18/relay-web-app.git",
          threads: [
            ThreadSummary(
              id: "demo-relay",
              title: "Trace delivery readiness",
              preview: "Read-only production review is complete.",
              cwd: "/Users/jordanrothstein/Desktop/GitHub/relay-web-app",
              repositoryRoot: "/Users/jordanrothstein/Desktop/GitHub/relay-web-app",
              source: "cli",
              status: .idle,
              controlLevel: .live,
              updatedAt: now.addingTimeInterval(-840)
            )
          ],
          updatedAt: now.addingTimeInterval(-840)
        ),
        ProjectSummary(
          id: "talky",
          name: "talky-web",
          repositoryRoot: "/Users/jordanrothstein/Desktop/GitHub/talky-web",
          gitOrigin: "git@github.com:jvroth18/talky-web.git",
          threads: talkyThreads,
          updatedAt: now.addingTimeInterval(-3_600)
        ),
      ],
      generatedAt: now
    )

    private static let talkyTitles = [
      "Fix voicemail transcript layout", "Add booking reminders", "Tune agent greeting",
      "Refactor call router", "Write onboarding copy", "Migrate billing webhook",
      "Add dark mode", "Speed up dashboard", "Audit accessibility",
    ]

    private static let talkyThreads: [ThreadSummary] = talkyTitles.enumerated().map {
      index, title in
      let position = index + 1
      return ThreadSummary(
        id: "demo-talky-\(position)",
        title: title,
        preview: "Saved CLI session.",
        cwd: "/Users/jordanrothstein/Desktop/GitHub/talky-web",
        repositoryRoot: "/Users/jordanrothstein/Desktop/GitHub/talky-web",
        source: "cli",
        status: position == 1 ? .idle : .notLoaded,
        controlLevel: position == 1 ? .live : .observe,
        updatedAt: now.addingTimeInterval(-Double(position) * 3_600)
      )
    }

    static let threadDetail = ThreadDetail(
      thread: liveThread,
      timeline: [
        TimelineItem(
          id: "demo-user",
          threadID: liveThread.id,
          turnID: "turn-live",
          kind: .user,
          state: .completed,
          title: "You",
          body:
            "Add phone and Mac diagnostics, including honest thermal state and measured data speed.",
          timestamp: now.addingTimeInterval(-70)
        ),
        TimelineItem(
          id: "demo-plan",
          threadID: liveThread.id,
          turnID: "turn-live",
          kind: .plan,
          state: .completed,
          title: "Plan",
          body:
            "✓ Add public-API telemetry\n✓ Measure encrypted bridge goodput\n• Validate on iPhone",
          timestamp: now.addingTimeInterval(-50)
        ),
        TimelineItem(
          id: "demo-command",
          threadID: liveThread.id,
          turnID: "turn-live",
          kind: .command,
          state: .completed,
          title: "xcodebuild test",
          body: "2 tests passed in 0.019 seconds",
          timestamp: now.addingTimeInterval(-32)
        ),
        TimelineItem(
          id: "demo-assistant",
          threadID: liveThread.id,
          turnID: "turn-live",
          kind: .assistant,
          state: .running,
          title: "Codex",
          body:
            "The native app is compiling cleanly. I’m checking the analytics layout on a real device now…",
          timestamp: now.addingTimeInterval(-8)
        ),
      ],
      pendingActions: [
        PendingAction(
          id: "demo-approval",
          threadID: liveThread.id,
          kind: .commandApproval,
          title: "Run xcodebuild test?",
          detail:
            "xcodebuild -scheme Eng -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test",
          options: [
            PendingActionOption(id: "accept", label: "Yes", detail: "Run this once"),
            PendingActionOption(
              id: "acceptForSession", label: "Yes to all", detail: "For this session"),
            PendingActionOption(id: "decline", label: "No"),
          ]
        )
      ]
    )

    static let phone = DeviceTelemetry(
      kind: .phone,
      name: "Jordan’s iPhone",
      sampledAt: now,
      cpuUsagePercent: 18.4,
      logicalCoreCount: 6,
      memoryUsedBytes: 5_420_000_000,
      memoryTotalBytes: 8_000_000_000,
      appResidentMemoryBytes: 82_000_000,
      diskFreeBytes: 164_000_000_000,
      diskTotalBytes: 512_000_000_000,
      batteryLevel: 0.74,
      powerState: .unplugged,
      lowPowerMode: false,
      thermalLevel: .nominal,
      uptimeSeconds: 142_800,
      interface: .wifi,
      downloadBytesPerSecond: 4_200_000,
      uploadBytesPerSecond: 680_000
    )

    static let mac = DeviceTelemetry(
      kind: .mac,
      name: "Jordan’s MacBook Pro",
      sampledAt: now,
      cpuUsagePercent: 31.8,
      logicalCoreCount: 12,
      memoryUsedBytes: 14_900_000_000,
      memoryTotalBytes: 19_327_000_000,
      appResidentMemoryBytes: 24_000_000,
      diskFreeBytes: 267_000_000_000,
      diskTotalBytes: 994_000_000_000,
      batteryLevel: 0.61,
      powerState: .charging,
      lowPowerMode: false,
      thermalLevel: .fair,
      uptimeSeconds: 518_400,
      interface: .wired,
      downloadBytesPerSecond: 8_500_000,
      uploadBytesPerSecond: 1_240_000
    )

    static let analytics = AnalyticsSnapshot(
      phone: phone,
      mac: mac,
      link: LinkTelemetry(
        sampledAt: now,
        roundTripMilliseconds: 14.2,
        measuredBytesPerSecond: 11_400_000,
        quality: .excellent,
        isExpensive: false,
        isConstrained: false
      )
    )

    static let phoneHistory = history(from: phone, phase: 0)
    static let macHistory = history(from: mac, phase: 1.4)

    private static func history(from source: DeviceTelemetry, phase: Double) -> [AnalyticsPoint] {
      (0..<32).map { index in
        let value = 24 + sin(Double(index) * 0.38 + phase) * 13
        return AnalyticsPoint(
          DeviceTelemetry(
            kind: source.kind,
            name: source.name,
            sampledAt: now.addingTimeInterval(Double(index - 31) * 2),
            cpuUsagePercent: value,
            logicalCoreCount: source.logicalCoreCount,
            memoryUsedBytes: source.memoryUsedBytes,
            memoryTotalBytes: source.memoryTotalBytes,
            thermalLevel: source.thermalLevel,
            uptimeSeconds: source.uptimeSeconds
          ))
      }
    }
  }
#endif
