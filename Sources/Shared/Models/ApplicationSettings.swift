import Foundation

enum NodeSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case name
  case latency

  var id: String { rawValue }
  var title: String { self == .name ? "名称" : "延迟" }
}

struct ApplicationSettings: Codable, Equatable, Sendable {
  var nodeSortMode: NodeSortMode = .name
  var autoSelectFastest = true
  var showFavoritesOnly = false
  var publicIPCheckURL = "https://api64.ipify.org?format=json"
  var iCloudSyncEnabled = false
  var onDemand = OnDemandSettings()

  private enum CodingKeys: String, CodingKey {
    case nodeSortMode, autoSelectFastest, showFavoritesOnly, publicIPCheckURL
    case iCloudSyncEnabled, onDemand
  }

  init(
    nodeSortMode: NodeSortMode = .name,
    autoSelectFastest: Bool = true,
    showFavoritesOnly: Bool = false,
    publicIPCheckURL: String = "https://api64.ipify.org?format=json",
    iCloudSyncEnabled: Bool = false,
    onDemand: OnDemandSettings = OnDemandSettings()
  ) {
    self.nodeSortMode = nodeSortMode
    self.autoSelectFastest = autoSelectFastest
    self.showFavoritesOnly = showFavoritesOnly
    self.publicIPCheckURL = publicIPCheckURL
    self.iCloudSyncEnabled = iCloudSyncEnabled
    self.onDemand = onDemand
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    nodeSortMode = try container.decodeIfPresent(NodeSortMode.self, forKey: .nodeSortMode) ?? .name
    autoSelectFastest = try container.decodeIfPresent(Bool.self, forKey: .autoSelectFastest) ?? true
    showFavoritesOnly =
      try container.decodeIfPresent(Bool.self, forKey: .showFavoritesOnly) ?? false
    publicIPCheckURL =
      try container.decodeIfPresent(String.self, forKey: .publicIPCheckURL)
      ?? "https://api64.ipify.org?format=json"
    iCloudSyncEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
    onDemand =
      try container.decodeIfPresent(OnDemandSettings.self, forKey: .onDemand)
      ?? OnDemandSettings()
  }
}

struct OnDemandSettings: Codable, Equatable, Sendable {
  var isEnabled = false
  var connectOnWiFi = true
  var connectOnCellular = true
  var excludedWiFiSSIDs: [String] = []

  var normalizedExcludedSSIDs: [String] {
    var seen = Set<String>()
    return excludedWiFiSSIDs.compactMap { value in
      let ssid = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return !ssid.isEmpty && seen.insert(ssid).inserted ? ssid : nil
    }
  }
}
