import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: BridgeStore
  @State private var selectedTab: EngTab =
    ProcessInfo.processInfo.arguments.contains("-eng-analytics") ? .analytics : .projects

  var body: some View {
    ZStack {
      EngCanvas()
      if store.isPaired {
        if ProcessInfo.processInfo.arguments.contains("-eng-thread"),
          let thread = store.projects.first?.threads.first
        {
          NavigationStack { ThreadView(thread: thread) }
        } else {
          TabView(selection: $selectedTab) {
            ProjectsView()
              .tabItem { Label("Projects", systemImage: "square.stack.3d.up.fill") }
              .tag(EngTab.projects)

            AnalyticsView()
              .tabItem { Label("Analytics", systemImage: "waveform.path.ecg.rectangle.fill") }
              .tag(EngTab.analytics)
          }
          .tint(EngDesign.cyan)
        }
      } else {
        ConnectionView()
      }
    }
    .alert(
      "Eng",
      isPresented: Binding(
        get: { store.presentedError != nil },
        set: { if !$0 { store.dismissError() } }
      )
    ) {
      Button("OK") { store.dismissError() }
    } message: {
      Text(store.presentedError?.message ?? "Something went wrong.")
    }
  }
}

private enum EngTab: Hashable {
  case projects
  case analytics
}

struct ConnectionPill: View {
  @EnvironmentObject private var store: BridgeStore

  var body: some View {
    HStack(spacing: 7) {
      StatusDot(
        color: store.isPaired ? EngDesign.mint : EngDesign.amber,
        pulsing: store.isPaired
      )
      Text(store.connectionLabel)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.07), in: Capsule())
    .overlay { Capsule().stroke(EngDesign.border, lineWidth: 1) }
  }
}
