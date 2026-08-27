import SwiftUI

@main
struct EngApp: App {
  @StateObject private var store = BridgeStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .task { store.start() }
    }
  }
}
