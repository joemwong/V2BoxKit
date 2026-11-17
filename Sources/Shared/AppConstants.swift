import Foundation

enum AppConstants {
  static let appGroupIdentifier = "group.top.ddddd.v2boxkit"
  static let tunnelBundleIdentifier = "top.ddddd.v2boxkit.PacketTunnel"
  static let vpnDescription = "V2BoxKit"
  static let backgroundRefreshIdentifier = "top.ddddd.v2boxkit.subscription-refresh"
  static let importURLScheme = "v2boxkit"

  static let nodesStorageKey = "storedNodes"
  static let subscriptionsStorageKey = "subscriptions"
  static let routingStorageKey = "routingSettings"
  static let selectedNodeStorageKey = "selectedNodeID"
  static let diagnosticsStorageKey = "diagnosticEvents"
  static let settingsStorageKey = "applicationSettings"

  static let latencyTestURL = "https://cp.cloudflare.com/generate_204"
}
