import EngCore
import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: BridgeStore
  @State private var selectedTab: EngTab = Self.initialTab

  private static var initialTab: EngTab {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-eng-analytics") { return .analytics }
      if ProcessInfo.processInfo.arguments.contains("-eng-config") { return .config }
    #endif
    return .projects
  }

  private static var showsDemoThread: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("-eng-thread")
    #else
      false
    #endif
  }

  var body: some View {
    ZStack {
      Win95.desktop.ignoresSafeArea()
      if store.isPaired {
        NavigationStack {
          Group {
            if Self.showsDemoThread, let thread = store.projects.first?.threads.first {
              ThreadView(thread: thread)
            } else {
              mainWindow
            }
          }
          .toolbar(.hidden, for: .navigationBar)
        }
      } else {
        ConnectionView()
      }
    }
    .overlay {
      if let error = store.presentedError {
        Win95MessageBox(title: "Eng", message: error.message) {
          store.dismissError()
        }
      }
    }
  }

  private var mainWindow: some View {
    Win95Window(title: "Eng", icon: "macbook.and.iphone") {
      VStack(spacing: 0) {
        if let notification = store.unreadNotification {
          unreadBanner(notification)
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        Win95Tabs(
          tabs: [
            Win95Tab(id: EngTab.projects, label: projectsTabLabel),
            Win95Tab(id: EngTab.analytics, label: "Analytics"),
            Win95Tab(id: EngTab.config, label: "Config"),
          ],
          selection: $selectedTab
        )
        .padding(.top, 4)
        .padding(.horizontal, 3)

        Group {
          switch selectedTab {
          case .projects: ProjectsView()
          case .analytics: AnalyticsView()
          case .config: ConfigView()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
        .raisedPanel()
        .padding(.horizontal, 3)

        Win95StatusBar(items: [
          store.connectionLabel,
          store.activePathLabel,
          store.bridgeName ?? "Mac",
        ])
        .padding(.horizontal, 3)
        .padding(.top, 3)
        .padding(.bottom, 2)
      }
      .animation(.easeInOut(duration: 0.18), value: store.unreadNotification)
    }
    .padding(6)
  }

  private var projectsTabLabel: String {
    store.displayedUnreadCount == 0
      ? "Projects" : "Projects (\(store.displayedUnreadCount))"
  }

  private func unreadBanner(_ notification: ThreadUnreadNotification) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "bell.fill")
        .foregroundStyle(Win95.warning)
      VStack(alignment: .leading, spacing: 1) {
        Text(notification.title)
          .font(Win95Font.bold)
          .lineLimit(1)
        Text(notification.detail)
          .font(Win95Font.small)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Button("Dismiss") { store.dismissUnreadNotification() }
        .buttonStyle(Win95ButtonStyle(compact: true))
    }
    .foregroundStyle(Win95.text)
    .padding(7)
    .background(Win95.face)
    .bevel(.raised)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Unread thread: \(notification.title), \(notification.detail)")
  }
}

private enum EngTab: Hashable {
  case projects
  case analytics
  case config
}
