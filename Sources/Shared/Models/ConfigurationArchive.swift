import Foundation

struct ConfigurationArchive: Codable, Equatable, Sendable {
  static let currentFormatVersion = 1

  let formatVersion: Int
  let createdAt: Date
  let nodes: [ProxyNode]
  let subscriptions: [ProxySubscription]
  let routing: RoutingSettings
  let settings: ApplicationSettings
  let selectedNodeID: UUID?

  init(
    formatVersion: Int = currentFormatVersion,
    createdAt: Date = Date(),
    nodes: [ProxyNode],
    subscriptions: [ProxySubscription],
    routing: RoutingSettings,
    settings: ApplicationSettings,
    selectedNodeID: UUID?
  ) {
    self.formatVersion = formatVersion
    self.createdAt = createdAt
    self.nodes = nodes
    self.subscriptions = subscriptions
    self.routing = routing
    self.settings = settings
    self.selectedNodeID = selectedNodeID
  }

  func validate() throws {
    guard formatVersion == Self.currentFormatVersion else {
      throw ConfigurationArchiveError.unsupportedVersion(formatVersion)
    }
    guard nodes.allSatisfy({ !$0.host.isEmpty && (1...65_535).contains($0.port) }) else {
      throw ConfigurationArchiveError.invalidContent
    }
    guard subscriptions.allSatisfy({ $0.url.scheme?.lowercased() == "https" }) else {
      throw ConfigurationArchiveError.invalidContent
    }
  }
}

enum ConfigurationArchiveError: LocalizedError {
  case unsupportedVersion(Int)
  case invalidContent

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version): "不支持的备份版本：\(version)"
    case .invalidContent: "备份内容校验失败"
    }
  }
}
