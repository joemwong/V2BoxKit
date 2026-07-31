import SwiftUI

@main
struct V2BoxKitApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var nodeStore = NodeStore()
  @StateObject private var tunnelManager = TunnelManager()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(nodeStore)
        .environmentObject(tunnelManager)
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      nodeStore.reloadFromDisk()
      Task { _ = await nodeStore.refreshAll(force: false) }
    }
  }
}
