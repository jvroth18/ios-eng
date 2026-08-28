import EngCore
import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: BridgeStore
  @State private var selectedTab: EngTab = Self.initialTab

  private static var initialTab: EngTab {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-eng-analytics") { return .analytics }
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
        Win95Tabs(
          tabs: [
            Win95Tab(id: EngTab.projects, label: "Projects"),
            Win95Tab(id: EngTab.analytics, label: "Analytics"),
          ],
          selection: $selectedTab
        )
        .padding(.top, 4)
        .padding(.horizontal, 3)

        Group {
          switch selectedTab {
          case .projects: ProjectsView()
          case .analytics: AnalyticsView()
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
    }
    .padding(6)
  }
}

private enum EngTab: Hashable {
  case projects
  case analytics
}
