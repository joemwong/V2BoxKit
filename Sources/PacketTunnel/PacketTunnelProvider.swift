import Darwin
import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
  enum ProviderError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration
    case tunnelFileDescriptorUnavailable

    var errorDescription: String? {
      switch self {
      case .missingConfiguration: "系统 VPN 配置中缺少节点信息"
      case .invalidConfiguration: "系统 VPN 配置无法解析"
      case .tunnelFileDescriptorUnavailable: "无法获取 iOS utun 文件描述符"
      }
    }
  }

  private let runtime = XrayRuntime()

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    do {
      let (node, routing) = try decodeProviderConfiguration()
      let settings = makeNetworkSettings(node: node, routing: routing)

      setTunnelNetworkSettings(settings) { [weak self] error in
        guard let self else {
          completionHandler(ProviderError.invalidConfiguration)
          return
        }
        if let error {
          DiagnosticLogStore.shared.append(
            .error, category: "provider", message: "设置隧道网络失败：\(error.localizedDescription)")
          completionHandler(error)
          return
        }

        do {
          guard let fileDescriptor = self.findTunnelFileDescriptor() else {
            throw ProviderError.tunnelFileDescriptorUnavailable
          }
          let baseConfiguration = try self.runtime.convertShareLink(node.rawURI)
          let configuration = try XrayConfigBuilder.build(
            baseConfiguration: baseConfiguration,
            tunnelFileDescriptor: fileDescriptor,
            routing: routing
          )
          try self.runtime.run(configurationJSON: configuration)
          DiagnosticLogStore.shared.append(.info, category: "provider", message: "Xray 隧道已启动")
          completionHandler(nil)
        } catch {
          self.runtime.stop()
          DiagnosticLogStore.shared.append(
            .error, category: "provider", message: "Xray 启动失败：\(error.localizedDescription)")
          completionHandler(error)
        }
      }
    } catch {
      DiagnosticLogStore.shared.append(
        .error, category: "provider", message: "VPN 配置无效：\(error.localizedDescription)")
      completionHandler(error)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    runtime.stop()
    DiagnosticLogStore.shared.append(
      .info, category: "provider", message: "Xray 隧道已停止（\(reason.rawValue)）")
    completionHandler()
  }

  override func handleAppMessage(
    _ messageData: Data,
    completionHandler: ((Data?) -> Void)? = nil
  ) {
    let response: [String: Any] = [
      "xrayVersion": runtime.version() ?? "unknown",
      "running": runtime.isRunning(),
    ]
    completionHandler?(try? JSONSerialization.data(withJSONObject: response))
  }

  private func decodeProviderConfiguration() throws -> (ProxyNode, RoutingSettings) {
    guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
      let providerConfiguration = tunnelProtocol.providerConfiguration,
      let nodeValue = providerConfiguration["node"] as? String,
      let routingValue = providerConfiguration["routing"] as? String
    else {
      throw ProviderError.missingConfiguration
    }
    guard let nodeData = Data(base64Encoded: nodeValue),
      let routingData = Data(base64Encoded: routingValue),
      let node = try? JSONDecoder().decode(ProxyNode.self, from: nodeData),
      let routing = try? JSONDecoder().decode(RoutingSettings.self, from: routingData)
    else {
      throw ProviderError.invalidConfiguration
    }
    return (node, routing)
  }

  private func makeNetworkSettings(
    node: ProxyNode,
    routing: RoutingSettings
  ) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: node.host)
    settings.mtu = NSNumber(value: routing.mtu)

    let ipv4 = NEIPv4Settings(addresses: ["172.19.0.2"], subnetMasks: ["255.255.255.0"])
    ipv4.includedRoutes = [.default()]
    if routing.mode == .rule, routing.bypassPrivateNetworks {
      ipv4.excludedRoutes = Self.privateIPv4Routes
    }
    settings.ipv4Settings = ipv4

    let ipv6 = NEIPv6Settings(addresses: ["fd00:19::2"], networkPrefixLengths: [64])
    ipv6.includedRoutes = [.default()]
    if routing.mode == .rule, routing.bypassPrivateNetworks {
      ipv6.excludedRoutes = Self.privateIPv6Routes
    }
    settings.ipv6Settings = ipv6

    let dns: NEDNSSettings
    switch routing.dns.mode {
    case .udp:
      dns = NEDNSSettings(servers: routing.dns.systemServers)
    case .doh:
      let encrypted = NEDNSOverHTTPSSettings(servers: routing.dns.systemServers)
      let value = routing.dns.normalizedServers[0]
      encrypted.serverURL = URL(
        string: value.hasPrefix("https://") ? value : "https://\(value)/dns-query")
      dns = encrypted
    case .dot:
      let encrypted = NEDNSOverTLSSettings(servers: routing.dns.systemServers)
      encrypted.serverName =
        routing.dns.normalizedServers[0]
        .replacingOccurrences(of: "tls://", with: "")
        .components(separatedBy: ":").first
      dns = encrypted
    }
    dns.matchDomains = [""]
    settings.dnsSettings = dns
    return settings
  }

  private func findTunnelFileDescriptor() -> Int32? {
    let systemControlProtocol: Int32 = 2
    let interfaceNameOption: Int32 = 2

    for descriptor in 0...1024 {
      let fileDescriptor = Int32(descriptor)
      var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
      var length = socklen_t(nameBuffer.count)
      let result = nameBuffer.withUnsafeMutableBytes { buffer in
        getsockopt(
          fileDescriptor,
          systemControlProtocol,
          interfaceNameOption,
          buffer.baseAddress,
          &length
        )
      }
      if result == 0, String(cString: nameBuffer).hasPrefix("utun") {
        return fileDescriptor
      }
    }
    return nil
  }

  private static let privateIPv4Routes = [
    NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
    NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
    NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
    NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
    NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
    NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
  ]

  private static let privateIPv6Routes = [
    NEIPv6Route(destinationAddress: "::1", networkPrefixLength: 128),
    NEIPv6Route(destinationAddress: "fc00::", networkPrefixLength: 7),
    NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10),
  ]
}
