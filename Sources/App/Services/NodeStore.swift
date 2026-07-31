import Combine
import Foundation

struct SubscriptionRefreshSummary: Sendable {
  let updated: Int
  let failed: Int
}

@MainActor
final class NodeStore: ObservableObject {
  @Published private(set) var nodes: [ProxyNode] = []
  @Published private(set) var subscriptions: [ProxySubscription] = []
  @Published private(set) var refreshingSubscriptionIDs = Set<UUID>()
  @Published private(set) var pingingNodeIDs = Set<UUID>()
  @Published var selectedNodeID: ProxyNode.ID? {
    didSet { persistSelectedNode() }
  }
  @Published var routing = RoutingSettings() {
    didSet { persistRouting() }
  }
  @Published var settings = ApplicationSettings() {
    didSet { persistSettings() }
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let subscriptionService = SubscriptionService()
  private let latencyService = LatencyService()
  private let cloudSyncService = CloudSyncService()
  private var cloudUploadTask: Task<Void, Never>?
  private var isRestoringArchive = false

  init(defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupIdentifier)) {
    self.defaults = defaults ?? .standard
    reloadFromDisk()
  }

  var selectedNode: ProxyNode? {
    nodes.first { $0.id == selectedNodeID }
  }

  var favoriteNodes: [ProxyNode] { nodes.filter(\.isFavorite) }

  var groups: [String] {
    Array(Set(nodes.map(\.groupName))).sorted { lhs, rhs in
      if lhs == "手动导入" { return true }
      if rhs == "手动导入" { return false }
      return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
  }

  func visibleNodes(searchText: String) -> [ProxyNode] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = nodes.filter { node in
      let matchesFavorite = !settings.showFavoritesOnly || node.isFavorite
      let matchesQuery =
        query.isEmpty
        || node.name.localizedCaseInsensitiveContains(query)
        || node.host.localizedCaseInsensitiveContains(query)
        || node.groupName.localizedCaseInsensitiveContains(query)
      return matchesFavorite && matchesQuery
    }
    return filtered.sorted(by: nodeComesBefore)
  }

  @discardableResult
  func importNodes(_ imported: [ProxyNode]) -> Int {
    var existingURIs = Set(nodes.map(\.rawURI))
    let unique = imported.filter { existingURIs.insert($0.rawURI).inserted }.map { node in
      var node = node
      node.source = .manual
      node.groupName = "手动导入"
      return node
    }
    nodes.append(contentsOf: unique)
    if selectedNodeID == nil { selectedNodeID = nodes.first?.id }
    persistNodes()
    return unique.count
  }

  @discardableResult
  func importPayload(_ text: String) throws -> Int {
    try importNodes(ShareLinkParser.parseMany(text))
  }

  func removeNodes(at offsets: IndexSet) {
    let visible = visibleNodes(searchText: "")
    let removedIDs = offsets.compactMap { visible.indices.contains($0) ? visible[$0].id : nil }
    nodes.removeAll { removedIDs.contains($0.id) }
    repairSelection(removedIDs: removedIDs)
    persistNodes()
  }

  func remove(_ node: ProxyNode) {
    nodes.removeAll { $0.id == node.id }
    repairSelection(removedIDs: [node.id])
    persistNodes()
  }

  func toggleFavorite(_ node: ProxyNode) {
    updateNode(node.id) { $0.isFavorite.toggle() }
  }

  func togglePinned(_ node: ProxyNode) {
    updateNode(node.id) { $0.isPinned.toggle() }
  }

  func addSubscription(
    name: String,
    url: URL,
    refreshInterval: SubscriptionRefreshInterval
  ) async throws {
    guard subscriptions.allSatisfy({ $0.url != url }) else {
      throw SubscriptionService.SubscriptionError.invalidResponse
    }

    var subscription = ProxySubscription(name: name, url: url, refreshInterval: refreshInterval)
    let result = try await subscriptionService.fetch(subscription: subscription)
    let now = Date()
    subscription.lastAttemptAt = now
    subscription.lastUpdatedAt = now
    subscription.etag = result.etag
    subscription.lastModified = result.lastModified
    subscriptions.append(subscription)
    subscriptions.sort(by: subscriptionComesBefore)
    if let newNodes = result.nodes {
      replaceNodes(for: subscription, with: newNodes)
    }
    persistSubscriptions()
  }

  @discardableResult
  func refreshSubscription(id: UUID, force: Bool = true) async -> Bool {
    guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return false }
    let current = subscriptions[index]
    if !force, !current.isDue() { return true }

    refreshingSubscriptionIDs.insert(id)
    defer { refreshingSubscriptionIDs.remove(id) }
    subscriptions[index].lastAttemptAt = Date()

    do {
      let result = try await subscriptionService.fetch(subscription: current)
      if let newNodes = result.nodes {
        replaceNodes(for: current, with: newNodes)
      }
      guard let latestIndex = subscriptions.firstIndex(where: { $0.id == id }) else { return false }
      subscriptions[latestIndex].lastUpdatedAt = Date()
      subscriptions[latestIndex].lastError = nil
      subscriptions[latestIndex].etag = result.etag
      subscriptions[latestIndex].lastModified = result.lastModified
      persistSubscriptions()
      DiagnosticLogStore.shared.append(
        .info, category: "subscription", message: "订阅更新成功：\(current.name)")
      return true
    } catch {
      if let latestIndex = subscriptions.firstIndex(where: { $0.id == id }) {
        subscriptions[latestIndex].lastError = error.localizedDescription
        persistSubscriptions()
      }
      DiagnosticLogStore.shared.append(
        .error, category: "subscription", message: "订阅更新失败：\(current.name)；保留旧节点")
      return false
    }
  }

  func refreshAll(force: Bool = true) async -> SubscriptionRefreshSummary {
    var updated = 0
    var failed = 0
    for subscription in subscriptions where subscription.isEnabled {
      if !force, !subscription.isDue() { continue }
      if await refreshSubscription(id: subscription.id, force: force) {
        updated += 1
      } else {
        failed += 1
      }
    }
    return SubscriptionRefreshSummary(updated: updated, failed: failed)
  }

  func updateSubscription(_ subscription: ProxySubscription) {
    guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
    let oldName = subscriptions[index].name
    subscriptions[index] = subscription
    if oldName != subscription.name {
      for nodeIndex in nodes.indices where nodes[nodeIndex].source.subscriptionID == subscription.id
      {
        nodes[nodeIndex].groupName = subscription.name
      }
      persistNodes()
    }
    subscriptions.sort(by: subscriptionComesBefore)
    persistSubscriptions()
  }

  func removeSubscription(_ subscription: ProxySubscription) {
    subscriptions.removeAll { $0.id == subscription.id }
    let removedIDs = nodes.filter { $0.source.subscriptionID == subscription.id }.map(\.id)
    nodes.removeAll { $0.source.subscriptionID == subscription.id }
    repairSelection(removedIDs: removedIDs)
    persistNodes()
    persistSubscriptions()
  }

  func measureLatency(for node: ProxyNode) async {
    guard !pingingNodeIDs.contains(node.id) else { return }
    pingingNodeIDs.insert(node.id)
    defer { pingingNodeIDs.remove(node.id) }
    let latency = await latencyService.measure(node: node)
    updateNode(node.id) {
      $0.latencyMilliseconds = latency
      $0.latencyMeasuredAt = Date()
    }
  }

  func measureAllLatencies(selectFastest: Bool? = nil) async {
    let snapshot = visibleNodes(searchText: "")
    for node in snapshot {
      guard !Task.isCancelled else { break }
      await measureLatency(for: node)
    }
    let shouldSelect = selectFastest ?? settings.autoSelectFastest
    if shouldSelect {
      selectedNodeID =
        nodes
        .filter { ($0.latencyMilliseconds ?? 10_000) < 10_000 }
        .min { ($0.latencyMilliseconds ?? .max) < ($1.latencyMilliseconds ?? .max) }?.id
        ?? selectedNodeID
    }
  }

  func reloadFromDisk() {
    if let data = defaults.data(forKey: AppConstants.nodesStorageKey),
      let storedNodes = try? decoder.decode([ProxyNode].self, from: data)
    {
      nodes = storedNodes
    }
    if let data = defaults.data(forKey: AppConstants.subscriptionsStorageKey),
      let storedSubscriptions = try? decoder.decode([ProxySubscription].self, from: data)
    {
      subscriptions = storedSubscriptions.sorted(by: subscriptionComesBefore)
    }
    if let data = defaults.data(forKey: AppConstants.routingStorageKey),
      let storedRouting = try? decoder.decode(RoutingSettings.self, from: data)
    {
      routing = storedRouting
    }
    if let data = defaults.data(forKey: AppConstants.settingsStorageKey),
      let storedSettings = try? decoder.decode(ApplicationSettings.self, from: data)
    {
      settings = storedSettings
    }
    if let rawID = defaults.string(forKey: AppConstants.selectedNodeStorageKey),
      let id = UUID(uuidString: rawID), nodes.contains(where: { $0.id == id })
    {
      selectedNodeID = id
    } else {
      selectedNodeID = nodes.first?.id
    }
  }

  func makeConfigurationArchive(createdAt: Date = Date()) -> ConfigurationArchive {
    ConfigurationArchive(
      createdAt: createdAt,
      nodes: nodes,
      subscriptions: subscriptions,
      routing: routing,
      settings: settings,
      selectedNodeID: selectedNodeID
    )
  }

  func restoreConfigurationArchive(_ archive: ConfigurationArchive) throws {
    try archive.validate()
    isRestoringArchive = true
    nodes = archive.nodes
    subscriptions = archive.subscriptions.sorted(by: subscriptionComesBefore)
    routing = archive.routing
    settings = archive.settings
    selectedNodeID =
      archive.selectedNodeID.flatMap { id in nodes.contains(where: { $0.id == id }) ? id : nil }
      ?? nodes.first?.id
    isRestoringArchive = false
    persistAll()
    DiagnosticLogStore.shared.append(
      .info,
      category: "backup",
      message: "已恢复 \(nodes.count) 个节点和 \(subscriptions.count) 个订阅"
    )
  }

  func uploadConfigurationToCloud() throws {
    try cloudSyncService.upload(makeConfigurationArchive())
    DiagnosticLogStore.shared.append(.info, category: "icloud", message: "配置已备份到 iCloud")
  }

  func restoreConfigurationFromCloud() throws {
    try restoreConfigurationArchive(cloudSyncService.download())
    DiagnosticLogStore.shared.append(.info, category: "icloud", message: "已从 iCloud 恢复配置")
  }

  func resetAllData() {
    nodes = []
    subscriptions = []
    selectedNodeID = nil
    routing = RoutingSettings()
    settings = ApplicationSettings()
    [
      AppConstants.nodesStorageKey,
      AppConstants.subscriptionsStorageKey,
      AppConstants.routingStorageKey,
      AppConstants.selectedNodeStorageKey,
      AppConstants.settingsStorageKey,
    ].forEach(defaults.removeObject)
  }

  private func replaceNodes(for subscription: ProxySubscription, with imported: [ProxyNode]) {
    let oldNodes = nodes.filter { $0.source.subscriptionID == subscription.id }
    let existingByURI = Dictionary(
      oldNodes.map { ($0.rawURI, $0) }, uniquingKeysWith: { first, _ in first })
    let replacements = imported.map { importedNode -> ProxyNode in
      if var existing = existingByURI[importedNode.rawURI] {
        existing.name = importedNode.name
        existing.groupName = subscription.name
        return existing
      }
      var node = importedNode
      node.source = .subscription(subscription.id)
      node.groupName = subscription.name
      return node
    }

    let removedIDs = oldNodes.map(\.id)
    nodes.removeAll { $0.source.subscriptionID == subscription.id }
    nodes.append(contentsOf: replacements)
    repairSelection(removedIDs: removedIDs, preferred: replacements.first?.id)
    persistNodes()
  }

  private func updateNode(_ id: UUID, mutation: (inout ProxyNode) -> Void) {
    guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
    mutation(&nodes[index])
    persistNodes()
  }

  private func repairSelection(removedIDs: [UUID], preferred: UUID? = nil) {
    if let selectedNodeID, removedIDs.contains(selectedNodeID) {
      self.selectedNodeID = preferred ?? visibleNodes(searchText: "").first?.id
    }
  }

  private func nodeComesBefore(_ lhs: ProxyNode, _ rhs: ProxyNode) -> Bool {
    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
    switch settings.nodeSortMode {
    case .name:
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    case .latency:
      let left = lhs.latencyMilliseconds ?? Int.max
      let right = rhs.latencyMilliseconds ?? Int.max
      if left != right { return left < right }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }

  private func subscriptionComesBefore(_ lhs: ProxySubscription, _ rhs: ProxySubscription) -> Bool {
    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
  }

  private func persistNodes() {
    guard !isRestoringArchive else { return }
    guard let data = try? encoder.encode(nodes) else { return }
    defaults.set(data, forKey: AppConstants.nodesStorageKey)
    scheduleCloudUpload()
  }

  private func persistSubscriptions() {
    guard !isRestoringArchive else { return }
    guard let data = try? encoder.encode(subscriptions) else { return }
    defaults.set(data, forKey: AppConstants.subscriptionsStorageKey)
    scheduleCloudUpload()
  }

  private func persistRouting() {
    guard !isRestoringArchive else { return }
    guard let data = try? encoder.encode(routing) else { return }
    defaults.set(data, forKey: AppConstants.routingStorageKey)
    scheduleCloudUpload()
  }

  private func persistSettings() {
    guard !isRestoringArchive else { return }
    guard let data = try? encoder.encode(settings) else { return }
    defaults.set(data, forKey: AppConstants.settingsStorageKey)
    scheduleCloudUpload()
  }

  private func persistSelectedNode() {
    guard !isRestoringArchive else { return }
    defaults.set(selectedNodeID?.uuidString, forKey: AppConstants.selectedNodeStorageKey)
    scheduleCloudUpload()
  }

  private func persistAll() {
    persistNodes()
    persistSubscriptions()
    persistRouting()
    persistSettings()
    persistSelectedNode()
  }

  private func scheduleCloudUpload() {
    guard settings.iCloudSyncEnabled else { return }
    let archive = makeConfigurationArchive()
    cloudUploadTask?.cancel()
    cloudUploadTask = Task { [cloudSyncService] in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      do {
        try cloudSyncService.upload(archive)
      } catch {
        DiagnosticLogStore.shared.append(
          .warning,
          category: "icloud",
          message: "iCloud 自动备份失败：\(error.localizedDescription)"
        )
      }
    }
  }
}
