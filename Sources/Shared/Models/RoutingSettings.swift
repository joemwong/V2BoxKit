import Foundation

enum RoutingMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case global
  case rule
  case direct

  var id: String { rawValue }

  var title: String {
    switch self {
    case .global: "全局代理"
    case .rule: "规则分流"
    case .direct: "全部直连"
    }
  }
}

enum DNSMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case udp
  case doh
  case dot

  var id: String { rawValue }

  var title: String {
    switch self {
    case .udp: "UDP/TCP"
    case .doh: "DNS over HTTPS"
    case .dot: "DNS over TLS"
    }
  }
}

struct DNSConfiguration: Codable, Equatable, Sendable {
  var mode: DNSMode = .udp
  var servers: [String] = ["1.1.1.1", "2606:4700:4700::1111"]
  var fallbackServer = "1.1.1.1"

  var normalizedServers: [String] {
    // Order is the user's priority: the first entry becomes the DoH/DoT endpoint.
    var seen = Set<String>()
    let values =
      servers
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
    return values.isEmpty ? ["1.1.1.1"] : values
  }

  /// Host of the primary server without scheme, port, path or IPv6 brackets.
  var primaryServerHost: String {
    let value = normalizedServers[0]
    let candidate: String
    if value.contains("://") {
      candidate = value
    } else if value.filter({ $0 == ":" }).count > 1, !value.hasPrefix("[") {
      candidate = "dns://[\(value)]"  // Bare IPv6 literal.
    } else {
      candidate = "dns://\(value)"
    }
    if let host = URLComponents(string: candidate)?.host, !host.isEmpty {
      return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
    return value
  }

  var xrayServers: [String] {
    normalizedServers.map { server in
      switch mode {
      case .udp:
        return server
      case .doh:
        return server.hasPrefix("https://") ? server : "https://\(server)/dns-query"
      case .dot:
        return server.hasPrefix("tls://") ? server : "tls://\(server)"
      }
    }
  }

  /// Servers for Xray's internal resolver. Xray-core has no DoT client, so DoT
  /// entries use DNS over TCP; the query still travels inside the proxy.
  var xrayCoreServers: [String] {
    switch mode {
    case .udp, .doh:
      return xrayServers
    case .dot:
      return normalizedServers.map { server in
        let host = DNSConfiguration(mode: .dot, servers: [server]).primaryServerHost
        return host.contains(":") ? "tcp://[\(host)]:53" : "tcp://\(host):53"
      }
    }
  }

  var systemServers: [String] {
    switch mode {
    case .udp:
      // An empty server list makes NEDNSSettings invalid and the tunnel fails to start.
      let plain = normalizedServers.filter { !$0.contains("://") }
      return plain.isEmpty ? [normalizedFallbackServer] : plain
    case .doh, .dot:
      return [normalizedFallbackServer]
    }
  }

  private var normalizedFallbackServer: String {
    let value = fallbackServer.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "1.1.1.1" : value
  }
}

enum RoutingRuleAction: String, Codable, CaseIterable, Identifiable, Sendable {
  case proxy
  case direct
  case block

  var id: String { rawValue }

  var title: String {
    switch self {
    case .proxy: "代理"
    case .direct: "直连"
    case .block: "拦截"
    }
  }
}

enum RoutingRuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case domain
  case ip

  var id: String { rawValue }
  var title: String { self == .domain ? "域名" : "IP/CIDR" }
}

struct RoutingRule: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  var name: String
  var kind: RoutingRuleKind
  var values: [String]
  var action: RoutingRuleAction
  var isEnabled: Bool

  init(
    id: UUID = UUID(),
    name: String,
    kind: RoutingRuleKind,
    values: [String] = [],
    action: RoutingRuleAction,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.values = values
    self.action = action
    self.isEnabled = isEnabled
  }

  var normalizedValues: [String] {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

struct LocalSharingSettings: Codable, Equatable, Sendable {
  var isEnabled = false
  var allowLocalNetwork = false
  var socksPort = 10_808
  var httpPort = 10_809
  var username = "v2boxkit"
  var password = String(
    UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
  ).lowercased()

  var listenAddress: String { allowLocalNetwork ? "0.0.0.0" : "127.0.0.1" }

  var isValid: Bool {
    (1...65_535).contains(socksPort)
      && (1...65_535).contains(httpPort)
      && socksPort != httpPort
      && !username.isEmpty
      && !password.isEmpty
  }
}

struct RoutingSettings: Codable, Equatable, Sendable {
  var mode: RoutingMode = .rule
  var bypassPrivateNetworks = true
  var directDomains: [String] = []
  var customRules: [RoutingRule] = []
  var dns = DNSConfiguration()
  var mtu = 1500
  var localSharing = LocalSharingSettings()

  private enum CodingKeys: String, CodingKey {
    case mode, bypassPrivateNetworks, directDomains, customRules, dns, mtu, localSharing
  }

  init(
    mode: RoutingMode = .rule,
    bypassPrivateNetworks: Bool = true,
    directDomains: [String] = [],
    customRules: [RoutingRule] = [],
    dns: DNSConfiguration = DNSConfiguration(),
    mtu: Int = 1500,
    localSharing: LocalSharingSettings = LocalSharingSettings()
  ) {
    self.mode = mode
    self.bypassPrivateNetworks = bypassPrivateNetworks
    self.directDomains = directDomains
    self.customRules = customRules
    self.dns = dns
    self.mtu = mtu
    self.localSharing = localSharing
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(RoutingMode.self, forKey: .mode) ?? .rule
    bypassPrivateNetworks =
      try container.decodeIfPresent(Bool.self, forKey: .bypassPrivateNetworks) ?? true
    directDomains = try container.decodeIfPresent([String].self, forKey: .directDomains) ?? []
    customRules = try container.decodeIfPresent([RoutingRule].self, forKey: .customRules) ?? []
    dns = try container.decodeIfPresent(DNSConfiguration.self, forKey: .dns) ?? DNSConfiguration()
    mtu = min(9_000, max(1_280, try container.decodeIfPresent(Int.self, forKey: .mtu) ?? 1_500))
    localSharing =
      try container.decodeIfPresent(LocalSharingSettings.self, forKey: .localSharing)
      ?? LocalSharingSettings()
  }

  var normalizedDirectDomains: [String] {
    var seen = Set<String>()
    return directDomains.compactMap { value in
      let domain =
        value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      guard !domain.isEmpty, !domain.contains(" "), seen.insert(domain).inserted else {
        return nil
      }
      return domain
    }
  }
}
