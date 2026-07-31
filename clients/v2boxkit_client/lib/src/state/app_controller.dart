import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../model/models.dart';
import '../services/share_link_parser.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../services/xray_bridge.dart';
import '../services/xray_config_builder.dart';

class AppController extends ChangeNotifier {
  AppController({
    StorageService? storage,
    SubscriptionService? subscriptions,
    ShareLinkParser? parser,
    XrayConfigBuilder? configBuilder,
    XrayBridge? bridge,
    Uuid? uuid,
  }) : _storage = storage ?? StorageService(),
       _subscriptionService = subscriptions ?? SubscriptionService(),
       _parser = parser ?? ShareLinkParser(),
       _configBuilder = configBuilder ?? const XrayConfigBuilder(),
       _bridge = bridge ?? XrayBridge.platform(),
       _uuid = uuid ?? const Uuid() {
    _eventSubscription = _bridge.events.listen(_handleTunnelEvent);
  }

  final StorageService _storage;
  final SubscriptionService _subscriptionService;
  final ShareLinkParser _parser;
  final XrayConfigBuilder _configBuilder;
  final XrayBridge _bridge;
  final Uuid _uuid;
  late final StreamSubscription<TunnelEvent> _eventSubscription;

  List<ProxyNode> _nodes = [];
  List<ProxySubscription> _subscriptions = [];
  RoutingSettings _routing = const RoutingSettings();
  String? _selectedNodeId;
  TunnelStatus _tunnelStatus = TunnelStatus.disconnected;
  String? _lastMessage;
  final Set<String> _measuringNodeIds = {};
  bool _busy = false;

  List<ProxyNode> get nodes => List.unmodifiable(_nodes);
  List<ProxySubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);
  RoutingSettings get routing => _routing;
  String? get selectedNodeId => _selectedNodeId;
  TunnelStatus get tunnelStatus => _tunnelStatus;
  String? get lastMessage => _lastMessage;
  Set<String> get measuringNodeIds => Set.unmodifiable(_measuringNodeIds);
  bool get busy => _busy;
  bool get isConnected =>
      _tunnelStatus == TunnelStatus.connected ||
      _tunnelStatus == TunnelStatus.connecting;

  ProxyNode? get selectedNode {
    for (final node in _nodes) {
      if (node.id == _selectedNodeId) return node;
    }
    return null;
  }

  AppSnapshot get snapshot => AppSnapshot(
    nodes: _nodes,
    subscriptions: _subscriptions,
    routing: _routing,
    selectedNodeId: _selectedNodeId,
  );

  Future<void> load() async {
    try {
      final value = await _storage.load();
      _applySnapshot(value);
    } catch (error) {
      _lastMessage = '本地配置读取失败，已使用安全默认值：$error';
      _applySnapshot(const AppSnapshot());
    }
    if (await _bridge.isRunning()) {
      _tunnelStatus = TunnelStatus.connected;
    }
    notifyListeners();
    unawaited(refreshDueSubscriptions());
  }

  List<ProxyNode> visibleNodes({
    String searchText = '',
    bool favoritesOnly = false,
  }) {
    final query = searchText.trim().toLowerCase();
    final result = _nodes.where((node) {
      if (favoritesOnly && !node.isFavorite) return false;
      return query.isEmpty ||
          node.name.toLowerCase().contains(query) ||
          node.host.toLowerCase().contains(query) ||
          node.groupName.toLowerCase().contains(query);
    }).toList();
    result.sort((left, right) {
      if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
      final leftLatency = left.latencyMilliseconds ?? 1 << 30;
      final rightLatency = right.latencyMilliseconds ?? 1 << 30;
      final latencyOrder = leftLatency.compareTo(rightLatency);
      if (latencyOrder != 0) return latencyOrder;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return result;
  }

  Future<int> importPayload(String payload) async {
    final imported = _parser.parseMany(payload);
    final known = _nodes.map((node) => node.rawUri).toSet();
    final unique = imported.where((node) => known.add(node.rawUri)).toList();
    if (unique.isEmpty) throw const FormatException('没有新的节点可导入');
    _nodes.addAll(unique);
    _selectedNodeId ??= unique.first.id;
    await _persist();
    _lastMessage = '已导入 ${unique.length} 个节点';
    notifyListeners();
    return unique.length;
  }

  Future<void> selectNode(String id) async {
    if (!_nodes.any((node) => node.id == id)) return;
    if (isConnected && id != _selectedNodeId) {
      throw StateError('请先断开连接再切换节点');
    }
    _selectedNodeId = id;
    await _persist();
    notifyListeners();
  }

  void toggleFavorite(String id) {
    _replaceNode(id, (node) => node.copyWith(isFavorite: !node.isFavorite));
  }

  void togglePinned(String id) {
    _replaceNode(id, (node) => node.copyWith(isPinned: !node.isPinned));
  }

  Future<void> removeNode(String id) async {
    if (isConnected && id == _selectedNodeId) {
      throw StateError('请先断开当前节点');
    }
    _nodes.removeWhere((node) => node.id == id);
    if (_selectedNodeId == id) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<ProxySubscription> addSubscription({
    required String name,
    required String url,
    int refreshHours = 24,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('请输入有效的 HTTPS 订阅地址');
    }
    final subscription = ProxySubscription(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? uri.host : name.trim(),
      url: uri,
      refreshHours: refreshHours,
    );
    _subscriptions.add(subscription);
    await _persist();
    notifyListeners();
    await refreshSubscription(subscription.id);
    return _subscriptionById(subscription.id);
  }

  Future<void> removeSubscription(String id) async {
    if (isConnected && selectedNode?.sourceId == id) {
      throw StateError('请先断开该订阅的当前节点');
    }
    _subscriptions.removeWhere((subscription) => subscription.id == id);
    final removedIds = _nodes
        .where((node) => node.sourceId == id)
        .map((node) => node.id)
        .toSet();
    _nodes.removeWhere((node) => node.sourceId == id);
    if (removedIds.contains(_selectedNodeId)) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> refreshSubscription(String id) async {
    final current = _subscriptionById(id);
    _setBusy(true);
    try {
      final response = await _subscriptionService.fetch(current);
      final now = DateTime.now();
      if (response.notModified) {
        _replaceSubscription(
          id,
          current.copyWith(
            lastUpdatedAt: now,
            etag: response.etag,
            lastModified: response.lastModified,
            clearError: true,
          ),
        );
      } else {
        final parsed = _parser.parseMany(
          response.body!,
          sourceId: id,
          groupName: current.name,
        );
        final previousByUri = {
          for (final node in _nodes.where((node) => node.sourceId == id))
            node.rawUri: node,
        };
        final refreshed = parsed.map((node) {
          final previous = previousByUri[node.rawUri];
          if (previous == null) return node;
          return node.copyWith(
            id: previous.id,
            isFavorite: previous.isFavorite,
            isPinned: previous.isPinned,
            latencyMilliseconds: previous.latencyMilliseconds,
            latencyMeasuredAt: previous.latencyMeasuredAt,
          );
        }).toList();
        final selectedRawUri = selectedNode?.sourceId == id
            ? selectedNode?.rawUri
            : null;
        _nodes.removeWhere((node) => node.sourceId == id);
        _nodes.addAll(refreshed);
        if (selectedRawUri != null) {
          _selectedNodeId = refreshed
              .where((node) => node.rawUri == selectedRawUri)
              .map((node) => node.id)
              .firstOrNull;
        }
        _selectedNodeId ??= refreshed.first.id;
        _replaceSubscription(
          id,
          current.copyWith(
            lastUpdatedAt: now,
            etag: response.etag,
            lastModified: response.lastModified,
            clearError: true,
          ),
        );
      }
      await _persist();
      _lastMessage = '订阅“${current.name}”更新完成';
    } catch (error) {
      _replaceSubscription(id, current.copyWith(lastError: error.toString()));
      await _persist();
      _lastMessage = '订阅“${current.name}”更新失败：$error';
      rethrow;
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<void> refreshDueSubscriptions() async {
    final due = _subscriptions
        .where((subscription) => subscription.isDue(DateTime.now()))
        .map((subscription) => subscription.id)
        .toList();
    for (final id in due) {
      try {
        await refreshSubscription(id);
      } catch (_) {
        // Each subscription records its own failure and keeps old nodes.
      }
    }
  }

  Future<void> refreshAllSubscriptions() async {
    for (final subscription in List.of(_subscriptions)) {
      try {
        await refreshSubscription(subscription.id);
      } catch (_) {
        // Continue refreshing independent subscriptions.
      }
    }
  }

  Future<void> connect() async {
    final node = selectedNode;
    if (node == null) throw StateError('请先选择一个节点');
    if (!_routing.localSharing.isValid) {
      throw const FormatException('本地代理分享必须设置用户名和密码');
    }
    _tunnelStatus = TunnelStatus.connecting;
    _lastMessage = null;
    notifyListeners();

    try {
      if (!await _bridge.requestPermission()) {
        throw StateError('用户未授予 VPN 权限');
      }
      final converted = await _bridge.invoke('convertShareLinksToXrayJson', {
        'text': node.rawUri,
      });
      converted.requireSuccess();
      if (converted.data is! Map) {
        throw const FormatException('节点转换结果不是 Xray 配置');
      }
      final base = (converted.data! as Map).cast<String, Object?>();
      final configuration = _configBuilder.build(base, _routing);
      await _bridge.start(
        jsonEncode(configuration),
        TunnelOptions(mtu: _routing.mtu, dnsServer: _routing.dnsServer),
      );
      if (Platform.isWindows) {
        _tunnelStatus = TunnelStatus.connected;
        _lastMessage = '已连接 ${node.name}';
      }
    } catch (error) {
      _tunnelStatus = TunnelStatus.error;
      _lastMessage = error.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _tunnelStatus = TunnelStatus.disconnecting;
    notifyListeners();
    try {
      await _bridge.stop();
      _tunnelStatus = TunnelStatus.disconnected;
      _lastMessage = '连接已断开';
    } catch (error) {
      _tunnelStatus = TunnelStatus.error;
      _lastMessage = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> measureLatency(String id) async {
    if (isConnected) {
      throw StateError('连接期间不能启动独立测速实例');
    }
    final index = _nodes.indexWhere((node) => node.id == id);
    if (index < 0 || _measuringNodeIds.contains(id)) return;
    final node = _nodes[index];
    _measuringNodeIds.add(id);
    notifyListeners();
    var delay = 10000;
    File? temporaryFile;
    try {
      final converted = await _bridge.invoke('convertShareLinksToXrayJson', {
        'text': node.rawUri,
      });
      converted.requireSuccess();
      final base = (converted.data! as Map).cast<String, Object?>();
      final configuration = _configBuilder.build(base, _routing);
      final directory = await getTemporaryDirectory();
      temporaryFile = File(
        '${directory.path}/v2boxkit-ping-${_uuid.v4()}.json',
      );
      await temporaryFile.writeAsString(jsonEncode(configuration), flush: true);
      final response = await _bridge.invoke('ping', {
        'configPath': temporaryFile.path,
        'timeout': 5,
        'url': 'https://cp.cloudflare.com/',
      });
      if (response.data is Map) {
        delay = ((response.data! as Map)['delay'] as num?)?.toInt() ?? 10000;
      } else {
        response.requireSuccess();
      }
    } catch (_) {
      delay = 10000;
    } finally {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      final currentIndex = _nodes.indexWhere((node) => node.id == id);
      if (currentIndex >= 0) {
        _nodes[currentIndex] = _nodes[currentIndex].copyWith(
          latencyMilliseconds: delay,
          latencyMeasuredAt: DateTime.now(),
        );
      }
      _measuringNodeIds.remove(id);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> measureAllLatencies() async {
    for (final node in List.of(_nodes)) {
      await measureLatency(node.id);
    }
  }

  Future<void> updateRouting(RoutingSettings value) async {
    if (isConnected) {
      throw StateError('请先断开连接再修改路由设置');
    }
    _routing = value;
    await _persist();
    notifyListeners();
  }

  Future<String?> exportBackup() => _storage.exportBackup(snapshot);

  Future<void> importBackup() async {
    if (isConnected) throw StateError('请先断开连接再恢复备份');
    final imported = await _storage.importBackup();
    if (imported == null) return;
    _applySnapshot(imported);
    await _persist();
    _lastMessage = '备份恢复完成';
    notifyListeners();
  }

  Future<Map<String, Object?>> diagnostics() async {
    String version = '不可用';
    bool runtimeRunning = false;
    try {
      final versionResponse = await _bridge.invoke('xrayVersion');
      if (versionResponse.data is Map) {
        version = (versionResponse.data! as Map)['version']?.toString() ?? '未知';
      }
      runtimeRunning = await _bridge.isRunning();
    } catch (error) {
      version = '加载失败：$error';
    }
    return {
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'xrayVersion': version,
      'runtimeRunning': runtimeRunning,
      'tunnelStatus': _tunnelStatus.name,
      'nodeCount': _nodes.length,
      'subscriptionCount': _subscriptions.length,
      'selectedProtocol': selectedNode?.kind.displayName ?? '未选择',
      'dnsServer': _routing.dnsServer,
      'mtu': _routing.mtu,
    };
  }

  void clearMessage() {
    _lastMessage = null;
    notifyListeners();
  }

  void _replaceNode(String id, ProxyNode Function(ProxyNode) transform) {
    final index = _nodes.indexWhere((node) => node.id == id);
    if (index < 0) return;
    _nodes[index] = transform(_nodes[index]);
    unawaited(_persist());
    notifyListeners();
  }

  ProxySubscription _subscriptionById(String id) {
    return _subscriptions.firstWhere(
      (subscription) => subscription.id == id,
      orElse: () => throw StateError('订阅不存在'),
    );
  }

  void _replaceSubscription(String id, ProxySubscription replacement) {
    final index = _subscriptions.indexWhere(
      (subscription) => subscription.id == id,
    );
    if (index >= 0) _subscriptions[index] = replacement;
  }

  void _applySnapshot(AppSnapshot value) {
    _nodes = List.of(value.nodes);
    _subscriptions = List.of(value.subscriptions);
    _routing = value.routing;
    _selectedNodeId = value.selectedNodeId;
    if (!_nodes.any((node) => node.id == _selectedNodeId)) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
    }
  }

  Future<void> _persist() => _storage.save(snapshot);

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  void _handleTunnelEvent(TunnelEvent event) {
    switch (event.status) {
      case 'connecting':
        _tunnelStatus = TunnelStatus.connecting;
      case 'connected':
        _tunnelStatus = TunnelStatus.connected;
        _lastMessage = selectedNode == null
            ? 'VPN 已连接'
            : '已连接 ${selectedNode!.name}';
      case 'disconnecting':
        _tunnelStatus = TunnelStatus.disconnecting;
      case 'disconnected':
        _tunnelStatus = TunnelStatus.disconnected;
      case 'error':
        _tunnelStatus = TunnelStatus.error;
        _lastMessage = event.message ?? 'VPN 原生服务失败';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_eventSubscription.cancel());
    _subscriptionService.close();
    _bridge.dispose();
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
