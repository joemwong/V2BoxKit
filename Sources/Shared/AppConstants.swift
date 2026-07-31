import Foundation

enum AppConstants {
  static let appGroupIdentifier = "group.com.example.V2BoxKit"
  static let tunnelBundleIdentifier = "com.example.V2BoxKit.PacketTunnel"
  static let vpnDescription = "V2BoxKit"
  static let backgroundRefreshIdentifier = "com.example.V2BoxKit.subscription-refresh"
  static let importURLScheme = "v2boxkit"

  static let nodesStorageKey = "storedNodes"
  static let subscriptionsStorageKey = "subscriptions"
  static let routingStorageKey = "routingSettings"
  static let selectedNodeStorageKey = "selectedNodeID"
  static let diagnosticsStorageKey = "diagnosticEvents"
  static let settingsStorageKey = "applicationSettings"

  static let latencyTestURL = "https://cp.cloudflare.com/generate_204"
}
