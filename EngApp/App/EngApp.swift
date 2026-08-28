import EngCore
import SwiftUI

@main
struct EngApp: App {
  @StateObject private var store = BridgeStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .preferredColorScheme(.light)
        .task { store.start() }
    }
  }
}
