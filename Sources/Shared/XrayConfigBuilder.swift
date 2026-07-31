import Foundation

enum XrayConfigBuilder {
  enum BuilderError: LocalizedError {
    case invalidBaseConfiguration
    case missingOutbound
    case serializationFailed

    var errorDescription: String? {
      switch self {
      case .invalidBaseConfiguration: "libXray 返回了无法识别的配置"
      case .missingOutbound: "配置中没有可用的出站节点"
      case .serializationFailed: "Xray 配置序列化失败"
      }
    }
  }

  static func build(
    baseConfiguration: Any,
    tunnelFileDescriptor: Int32,
    routing: RoutingSettings
  ) throws -> String {
    guard var configuration = baseConfiguration as? [String: Any] else {
      throw BuilderError.invalidBaseConfiguration
    }
    guard var outbounds = configuration["outbounds"] as? [[String: Any]],
      !outbounds.isEmpty
    else {
      throw BuilderError.missingOutbound
    }

    outbounds[0]["tag"] = "proxy"
    let managedTags = Set(["direct", "block"])
    outbounds.removeAll { outbound in
      guard let tag = outbound["tag"] as? String else { return false }
      return managedTags.contains(tag)
    }
    outbounds.append(["tag": "direct", "protocol": "freedom"])
    outbounds.append(["tag": "block", "protocol": "blackhole"])

    configuration["outbounds"] = outbounds
    var inbounds: [[String: Any]] = [
      [
        "tag": "tun-in",
        "protocol": "tun",
        "settings": [
          "name": "utun",
          "mtu": routing.mtu,
        ],
        "sniffing": [
          "enabled": true,
          "destOverride": ["http", "tls", "quic"],
        ],
      ]
    ]
    if routing.localSharing.isEnabled, routing.localSharing.isValid {
      let sharing = routing.localSharing
      let accounts = [["user": sharing.username, "pass": sharing.password]]
      inbounds.append([
        "tag": "local-socks-in",
        "listen": sharing.listenAddress,
        "port": sharing.socksPort,
        "protocol": "socks",
        "settings": [
          "auth": "password",
          "accounts": accounts,
          "udp": true,
        ],
        "sniffing": [
          "enabled": true,
          "destOverride": ["http", "tls", "quic"],
        ],
      ])
      inbounds.append([
        "tag": "local-http-in",
        "listen": sharing.listenAddress,
        "port": sharing.httpPort,
        "protocol": "http",
        "settings": ["accounts": accounts],
        "sniffing": [
          "enabled": true,
          "destOverride": ["http", "tls"],
        ],
      ])
    }
    configuration["inbounds"] = inbounds
    configuration["env"] = [
      "xray.tun.fd": String(tunnelFileDescriptor)
    ]
    configuration["log"] = ["loglevel": "warning"]
    configuration["routing"] = [
      "domainStrategy": "IPIfNonMatch",
      "rules": routingRules(for: routing),
    ]

    guard JSONSerialization.isValidJSONObject(configuration),
      let data = try? JSONSerialization.data(withJSONObject: configuration)
    else {
      throw BuilderError.serializationFailed
    }
    return String(decoding: data, as: UTF8.self)
  }

  private static func routingRules(for routing: RoutingSettings) -> [[String: Any]] {
    switch routing.mode {
    case .global:
      return []

    case .direct:
      return [
        [
          "type": "field",
          "network": "tcp,udp",
          "outboundTag": "direct",
        ]
      ]

    case .rule:
      var rules: [[String: Any]] = []
      rules.append(contentsOf: customRoutingRules(routing.customRules))
      if routing.bypassPrivateNetworks {
        rules.append([
          "type": "field",
          "ip": privateNetworkCIDRs,
          "outboundTag": "direct",
        ])
      }
      let domains = routing.normalizedDirectDomains.map { "domain:\($0)" }
      if !domains.isEmpty {
        rules.append([
          "type": "field",
          "domain": domains,
          "outboundTag": "direct",
        ])
      }
      return rules
    }
  }

  private static func customRoutingRules(_ rules: [RoutingRule]) -> [[String: Any]] {
    rules.compactMap { rule in
      guard rule.isEnabled, !rule.normalizedValues.isEmpty else { return nil }

      let outboundTag: String
      switch rule.action {
      case .proxy: outboundTag = "proxy"
      case .direct: outboundTag = "direct"
      case .block: outboundTag = "block"
      }

      var result: [String: Any] = [
        "type": "field",
        "outboundTag": outboundTag,
      ]
      switch rule.kind {
      case .domain:
        result["domain"] = rule.normalizedValues.map { value in
          if value.hasPrefix("domain:") || value.hasPrefix("full:") || value.hasPrefix("regexp:") {
            return value
          }
          return "domain:\(value.lowercased())"
        }
      case .ip:
        result["ip"] = rule.normalizedValues
      }
      return result
    }
  }

  private static let privateNetworkCIDRs = [
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "224.0.0.0/4",
    "::1/128",
    "fc00::/7",
    "fe80::/10",
    "ff00::/8",
  ]
}
