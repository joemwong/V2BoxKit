import Combine
@preconcurrency import Foundation
@preconcurrency import NetworkExtension

/// Bridges the legacy callback result into `TunnelManager`'s main-actor context.
/// The managers are only accessed after the continuation resumes on that actor.
private struct TunnelManagerList: @unchecked Sendable {
  let managers: [NETunnelProviderManager]
}

@MainActor
final class TunnelManager: ObservableObject {
  enum ManagerError: LocalizedError {
    case notConfigured

    var errorDescription: String? { "请先手动连接一次，创建系统 VPN 配置" }
  }

  @Published private(set) var status: NEVPNStatus = .invalid
  @Published private(set) var isWorking = false
  /// Node baked into the saved VPN configuration (the one the tunnel runs).
  @Published private(set) var activeNodeID: UUID?

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
    let activeManager = try await saveConfiguration(node: node, routing: routing, onDemand: onDemand)
    try start(activeManager)
  }

  /// Switches a running tunnel to another node or new routing settings without
  /// making the user disconnect and reconnect by hand.
  func reconnect(
    node: ProxyNode,
    routing: RoutingSettings,
    onDemand: OnDemandSettings
  ) async throws {
    guard isConnected, manager != nil else {
      try await connect(node: node, routing: routing, onDemand: onDemand)
      return
    }
    isWorking = true
    defer { isWorking = false }
    // Save first: if on-demand restarts the tunnel after the stop below, it
    // already picks up the new configuration.
    let activeManager = try await saveConfiguration(node: node, routing: routing, onDemand: onDemand)
    activeManager.connection.stopVPNTunnel()
    await waitForStatus(in: [.disconnected, .invalid, .connecting, .connected], after: .disconnecting)
    if activeManager.connection.status == .disconnected || activeManager.connection.status == .invalid {
      try start(activeManager)
    }
    DiagnosticLogStore.shared.append(.info, category: "tunnel", message: "已切换到节点：\(node.name)")
  }

  private func start(_ activeManager: NETunnelProviderManager) throws {
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

  /// Waits (max ~8 s) until the connection has left `transient` and reached one
  /// of `targets`. Polling is enough here; status notifications also update UI.
  private func waitForStatus(in targets: Set<NEVPNStatus>, after transient: NEVPNStatus) async {
    let deadline = Date().addingTimeInterval(8)
    var sawTransient = false
    while Date() < deadline {
      let current = manager?.connection.status ?? .invalid
      if current == transient { sawTransient = true }
      // Ignore the still-connected state seen right after stop was requested.
      if targets.contains(current), sawTransient || current != .connected { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  private func saveConfiguration(
    node: ProxyNode,
    routing: RoutingSettings,
    onDemand: OnDemandSettings
  ) async throws -> NETunnelProviderManager {
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
    // With includeAllNetworks, iOS ignores the provider's excludedRoutes for LAN traffic, so the
    // "bypass private networks" option (and direct mode) also needs this switch to keep LAN
    // devices (printers, AirPlay, NAS) reachable.
    tunnelProtocol.excludeLocalNetworks =
      routing.mode == .direct || (routing.mode == .rule && routing.bypassPrivateNetworks)

    activeManager.localizedDescription = AppConstants.vpnDescription
    activeManager.protocolConfiguration = tunnelProtocol
    activeManager.isEnabled = true
    applyOnDemand(onDemand, to: activeManager)
    try await save(activeManager)
    try await load(activeManager)

    manager = activeManager
    refreshStatus()
    return activeManager
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
    activeNodeID = Self.configuredNodeID(of: manager)
  }

  private static func configuredNodeID(of manager: NETunnelProviderManager?) -> UUID? {
    guard
      let config = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?
        .providerConfiguration,
      let value = config["node"] as? String,
      let data = Data(base64Encoded: value),
      let node = try? JSONDecoder().decode(ProxyNode.self, from: data)
    else { return nil }
    return node.id
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
    let result: TunnelManagerList = try await withCheckedThrowingContinuation(isolation: MainActor.shared) {
      (continuation: CheckedContinuation<TunnelManagerList, any Error>) in
      NETunnelProviderManager.loadAllFromPreferences { managers, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: TunnelManagerList(managers: managers ?? []))
        }
      }
    }
    return result.managers
  }

  private func save(_ manager: NETunnelProviderManager) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
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
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
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
