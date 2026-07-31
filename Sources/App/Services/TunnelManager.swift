import Combine
import Foundation
import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
  enum ManagerError: LocalizedError {
    case notConfigured

    var errorDescription: String? { "请先手动连接一次，创建系统 VPN 配置" }
  }

  @Published private(set) var status: NEVPNStatus = .invalid
  @Published private(set) var isWorking = false

  private var manager: NETunnelProviderManager?
  private var statusObserver: NSObjectProtocol?

  init() {
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refreshStatus() }
    }
    Task { try? await prepare() }
  }

  deinit {
    if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
  }

  var isConnected: Bool { status == .connected || status == .connecting || status == .reasserting }

  var statusText: String {
    switch status {
    case .invalid: "未配置"
    case .disconnected: "未连接"
    case .connecting: "连接中"
    case .connected: "已连接"
    case .reasserting: "重连中"
    case .disconnecting: "断开中"
    @unknown default: "未知"
    }
  }

  func prepare() async throws {
    let managers = try await loadAllManagers()
    manager = managers.first(where: { $0.localizedDescription == AppConstants.vpnDescription })
    refreshStatus()
  }

  func toggle(
    node: ProxyNode,
    routing: RoutingSettings,
    onDemand: OnDemandSettings
  ) async throws {
    if isConnected {
      if let manager, manager.isOnDemandEnabled {
        manager.isOnDemandEnabled = false
        try await save(manager)
        try await load(manager)
      }
      manager?.connection.stopVPNTunnel()
      DiagnosticLogStore.shared.append(.info, category: "tunnel", message: "已请求停止 VPN")
      return
    }
    try await connect(node: node, routing: routing, onDemand: onDemand)
  }

  func connect(
    node: ProxyNode,
    routing: RoutingSettings,
    onDemand: OnDemandSettings
  ) async throws {
    isWorking = true
    defer { isWorking = false }

    let activeManager = manager ?? NETunnelProviderManager()
    let nodeData = try JSONEncoder().encode(node)
    let routingData = try JSONEncoder().encode(routing)

    let tunnelProtocol = NETunnelProviderProtocol()
    tunnelProtocol.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
    tunnelProtocol.serverAddress = node.host
    tunnelProtocol.providerConfiguration = [
      "node": nodeData.base64EncodedString(),
      "routing": routingData.base64EncodedString(),
    ]
    tunnelProtocol.includeAllNetworks = true

    activeManager.localizedDescription = AppConstants.vpnDescription
    activeManager.protocolConfiguration = tunnelProtocol
    activeManager.isEnabled = true
    applyOnDemand(onDemand, to: activeManager)
    try await save(activeManager)
    try await load(activeManager)

    manager = activeManager
    do {
      try activeManager.connection.startVPNTunnel()
      DiagnosticLogStore.shared.append(.info, category: "tunnel", message: "已请求启动 VPN")
    } catch {
      DiagnosticLogStore.shared.append(
        .error, category: "tunnel", message: "启动 VPN 失败：\(error.localizedDescription)")
      throw error
    }
    refreshStatus()
  }

  func runtimeInfo() async throws -> String {
    guard let session = manager?.connection as? NETunnelProviderSession else {
      return "VPN 尚未配置"
    }
    let data: Data = try await withCheckedThrowingContinuation { continuation in
      do {
        try session.sendProviderMessage(Data("status".utf8)) { response in
          continuation.resume(returning: response ?? Data())
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return "核心未运行（VPN 状态：\(statusText)）"
    }
    let version = object["xrayVersion"] as? String ?? "unknown"
    let running = object["running"] as? Bool ?? false
    return "Xray \(version) · \(running ? "运行中" : "未运行")"
  }

  func resetConfiguration() async {
    manager?.connection.stopVPNTunnel()
    if let manager {
      await withCheckedContinuation { continuation in
        manager.removeFromPreferences { _ in continuation.resume(returning: ()) }
      }
    }
    self.manager = nil
    refreshStatus()
  }

  func configureOnDemand(_ settings: OnDemandSettings) async throws {
    guard let manager else { throw ManagerError.notConfigured }
    applyOnDemand(settings, to: manager)
    try await save(manager)
    try await load(manager)
    DiagnosticLogStore.shared.append(
      .info,
      category: "on-demand",
      message: settings.isEnabled ? "按需连接已启用" : "按需连接已关闭"
    )
  }

  private func refreshStatus() {
    status = manager?.connection.status ?? .invalid
  }

  private func applyOnDemand(
    _ settings: OnDemandSettings,
    to manager: NETunnelProviderManager
  ) {
    guard settings.isEnabled else {
      manager.onDemandRules = nil
      manager.isOnDemandEnabled = false
      return
    }

    var rules: [NEOnDemandRule] = []
    if !settings.normalizedExcludedSSIDs.isEmpty {
      let excludedWiFi = NEOnDemandRuleDisconnect()
      excludedWiFi.interfaceTypeMatch = .wiFi
      excludedWiFi.ssidMatch = settings.normalizedExcludedSSIDs
      rules.append(excludedWiFi)
    }

    let wiFiRule: NEOnDemandRule =
      settings.connectOnWiFi ? NEOnDemandRuleConnect() : NEOnDemandRuleDisconnect()
    wiFiRule.interfaceTypeMatch = .wiFi
    rules.append(wiFiRule)

    let cellularRule: NEOnDemandRule =
      settings.connectOnCellular ? NEOnDemandRuleConnect() : NEOnDemandRuleDisconnect()
    cellularRule.interfaceTypeMatch = .cellular
    rules.append(cellularRule)

    rules.append(NEOnDemandRuleDisconnect())
    manager.onDemandRules = rules
    manager.isOnDemandEnabled = true
  }

  private func loadAllManagers() async throws -> [NETunnelProviderManager] {
    try await withCheckedThrowingContinuation { continuation in
      NETunnelProviderManager.loadAllFromPreferences { managers, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: managers ?? [])
        }
      }
    }
  }

  private func save(_ manager: NETunnelProviderManager) async throws {
    try await withCheckedThrowingContinuation { continuation in
      manager.saveToPreferences { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private func load(_ manager: NETunnelProviderManager) async throws {
    try await withCheckedThrowingContinuation { continuation in
      manager.loadFromPreferences { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }
}
