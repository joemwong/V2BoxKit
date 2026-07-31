import Foundation

enum ProxyProtocol: String, Codable, CaseIterable, Sendable {
  case vless
  case vmess
  case trojan
  case shadowsocks = "ss"
  case hysteria2

  var displayName: String {
    switch self {
    case .vless: "VLESS"
    case .vmess: "VMess"
    case .trojan: "Trojan"
    case .shadowsocks: "Shadowsocks"
    case .hysteria2: "Hysteria 2"
    }
  }
}

enum NodeSource: Codable, Hashable, Sendable {
  case manual
  case subscription(UUID)

  var subscriptionID: UUID? {
    if case .subscription(let id) = self { return id }
    return nil
  }
}

struct ProxyNode: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var name: String
  let kind: ProxyProtocol
  let host: String
  let port: Int
  let rawURI: String
  var source: NodeSource
  var groupName: String
  var isFavorite: Bool
  var isPinned: Bool
  var latencyMilliseconds: Int?
  var latencyMeasuredAt: Date?

  init(
    id: UUID = UUID(),
    name: String,
    kind: ProxyProtocol,
    host: String,
    port: Int,
    rawURI: String,
    source: NodeSource = .manual,
    groupName: String = "手动导入",
    isFavorite: Bool = false,
    isPinned: Bool = false,
    latencyMilliseconds: Int? = nil,
    latencyMeasuredAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.host = host
    self.port = port
    self.rawURI = rawURI
    self.source = source
    self.groupName = groupName
    self.isFavorite = isFavorite
    self.isPinned = isPinned
    self.latencyMilliseconds = latencyMilliseconds
    self.latencyMeasuredAt = latencyMeasuredAt
  }

  var endpoint: String { "\(host):\(port)" }

  var latencyText: String {
    guard let latencyMilliseconds else { return "—" }
    if latencyMilliseconds >= 10_000 { return "失败" }
    return "\(latencyMilliseconds) ms"
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, kind, host, port, rawURI, source, groupName
    case isFavorite, isPinned, latencyMilliseconds, latencyMeasuredAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    kind = try container.decode(ProxyProtocol.self, forKey: .kind)
    host = try container.decode(String.self, forKey: .host)
    port = try container.decode(Int.self, forKey: .port)
    rawURI = try container.decode(String.self, forKey: .rawURI)
    source = try container.decodeIfPresent(NodeSource.self, forKey: .source) ?? .manual
    groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? "手动导入"
    isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    latencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds)
    latencyMeasuredAt = try container.decodeIfPresent(Date.self, forKey: .latencyMeasuredAt)
  }
}
