import Foundation

enum SubscriptionRefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
  case manual = 0
  case sixHours = 6
  case twelveHours = 12
  case daily = 24
  case weekly = 168

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .manual: "手动"
    case .sixHours: "每 6 小时"
    case .twelveHours: "每 12 小时"
    case .daily: "每天"
    case .weekly: "每周"
    }
  }

  var timeInterval: TimeInterval? {
    self == .manual ? nil : TimeInterval(rawValue * 3600)
  }
}

struct ProxySubscription: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var name: String
  var url: URL
  var isEnabled: Bool
  var refreshInterval: SubscriptionRefreshInterval
  var lastUpdatedAt: Date?
  var lastAttemptAt: Date?
  var lastError: String?
  var etag: String?
  var lastModified: String?
  var isPinned: Bool

  init(
    id: UUID = UUID(),
    name: String,
    url: URL,
    isEnabled: Bool = true,
    refreshInterval: SubscriptionRefreshInterval = .daily,
    lastUpdatedAt: Date? = nil,
    lastAttemptAt: Date? = nil,
    lastError: String? = nil,
    etag: String? = nil,
    lastModified: String? = nil,
    isPinned: Bool = false
  ) {
    self.id = id
    self.name = name
    self.url = url
    self.isEnabled = isEnabled
    self.refreshInterval = refreshInterval
    self.lastUpdatedAt = lastUpdatedAt
    self.lastAttemptAt = lastAttemptAt
    self.lastError = lastError
    self.etag = etag
    self.lastModified = lastModified
    self.isPinned = isPinned
  }

  func isDue(at date: Date = Date()) -> Bool {
    guard isEnabled, let interval = refreshInterval.timeInterval else { return false }
    guard let lastUpdatedAt else { return true }
    return date.timeIntervalSince(lastUpdatedAt) >= interval
  }
}
