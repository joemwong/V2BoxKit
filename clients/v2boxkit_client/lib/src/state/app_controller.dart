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
  // A counter, not a bool: concurrent refreshes (auto + manual) used to clear
  // the busy flag as soon as the first one finished.
  int _busyCount = 0;
  bool _measuringAll = false;
  Timer? _disconnectFallback;

  List<ProxyNode> get nodes => List.unmodifiable(_nodes);
  List<ProxySubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);
  RoutingSettings get routing => _routing;
  String? get selectedNodeId => _selectedNodeId;
  TunnelStatus get tunnelStatus => _tunnelStatus;
  String? get lastMessage => _lastMessage;
  Set<String> get measuringNodeIds => Set.unmodifiable(_measuringNodeIds);
  bool get busy => _busyCount > 0;
  bool get measuringAll => _measuringAll;
  bool get isTransitioning =>
      _tunnelStatus == TunnelStatus.connecting ||
      _tunnelStatus == TunnelStatus.disconnecting;
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
    if (id == _selectedNodeId) return;
    final wasConnected = _tunnelStatus == TunnelStatus.connected;
    if (_tunnelStatus == TunnelStatus.connecting ||
        _tunnelStatus == TunnelStatus.disconnecting) {
      throw StateError('正在切换连接状态，请稍候');
    }
    _selectedNodeId = id;
    await _persist();
    notifyListeners();
    // Switch nodes in place instead of forcing disconnect → select → connect.
    if (wasConnected) await _restartTunnel();
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
      // The subscription may have been removed while the request was in
      // flight; re-adding its nodes would leave undeletable orphans.
      if (!_subscriptions.any((subscription) => subscription.id == id)) return;
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

  Future<void> connect() => _startTunnel(requestPermission: true);

  /// Applies a new node or new routing settings to a running tunnel.
  Future<void> _restartTunnel() async {
    if (Platform.isWindows) {
      // libXray refuses to run a second instance; stop the old one first.
      try {
        await _bridge.stop();
      } catch (error) {
        // Without this the status stayed `disconnecting` forever and locked
        // the connect button and routing page.
        _tunnelStatus = TunnelStatus.error;
        _lastMessage = error.toString();
        notifyListeners();
        rethrow;
      }
    }
    // On Android the VPN service tears down the old runtime itself before
    // re-establishing, so the system VPN key icon never drops.
    await _startTunnel(requestPermission: false);
  }

  Future<void> _startTunnel({required bool requestPermission}) async {
    final node = selectedNode;
    if (node == null) throw StateError('请先选择一个节点');
    if (!_routing.localSharing.isValid) {
      throw const FormatException('本地代理分享必须设置用户名和密码');
    }
    _tunnelStatus = TunnelStatus.connecting;
    _lastMessage = null;
    notifyListeners();

    try {
      if (requestPermission && !await _bridge.requestPermission()) {
        throw StateError('用户未授予 VPN 权限');
      }
      final converted = await _bridge.invoke('convertShareLinksToXrayJson', {
        'text': _parser.normalizeRuntimeUri(node.rawUri),
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
      if (Platform.isAndroid) {
        // stop() only sends the intent; the service reports `disconnected`
        // once teardown finishes. Showing it earlier let users reconnect into
        // a half-stopped service. Fall back in case the event is lost.
        _disconnectFallback?.cancel();
        _disconnectFallback = Timer(const Duration(seconds: 6), () {
          if (_tunnelStatus == TunnelStatus.disconnecting) {
            _tunnelStatus = TunnelStatus.disconnected;
            _lastMessage = '连接已断开';
            notifyListeners();
          }
        });
      } else {
        _tunnelStatus = TunnelStatus.disconnected;
        _lastMessage = '连接已断开';
      }
    } catch (error) {
      _tunnelStatus = TunnelStatus.error;
      _lastMessage = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> measureLatency(
    String id, {
    bool persist = true,
    int? port,
  }) async {
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
        'text': _parser.normalizeRuntimeUri(node.rawUri),
      });
      converted.requireSuccess();
      final base = (converted.data! as Map).cast<String, Object?>();
      final probePort = port ?? (await _freePorts(1)).first;
      // Probe-only config: the full tunnel config would start a second tun
      // (on Windows: a Wintun adapter that rewrites routes) and could route
      // the probe through `direct` instead of the node.
      final configuration = _configBuilder.buildLatencyProbe(base, probePort);
      final directory = await getTemporaryDirectory();
      temporaryFile = File(
        '${directory.path}/v2boxkit-ping-${_uuid.v4()}.json',
      );
      await temporaryFile.writeAsString(jsonEncode(configuration), flush: true);
      final response = await _bridge.invoke('ping', {
        'configPath': temporaryFile.path,
        'timeout': 5,
        'url': 'https://cp.cloudflare.com/generate_204',
        'proxy': 'socks5://127.0.0.1:$probePort',
      });
      response.requireSuccess();
      if (response.data is Map) {
        delay = ((response.data! as Map)['delay'] as num?)?.toInt() ?? 10000;
      }
    } catch (error) {
      delay = 10000;
      _lastMessage = '节点“${node.name}”测速失败：$error';
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
      if (persist) await _persist();
      notifyListeners();
    }
  }

  Future<void> measureAllLatencies() async {
    if (_measuringAll) return;
    _measuringAll = true;
    notifyListeners();
    final queue = List.of(_nodes.map((node) => node.id));
    // Reserve distinct ports up front: parallel probes asking one at a time
    // could be handed the same port, and one of them would fail.
    var ports = <int>[];
    try {
      ports = await _freePorts(queue.length);
    } catch (_) {
      // Fall back to per-probe allocation.
    }
    final portById = <String, int>{
      for (var i = 0; i < queue.length && i < ports.length; i++)
        queue[i]: ports[i],
    };
    // A few probes in parallel: each can block for the full timeout, so
    // serial testing took N × 5 s.
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        // Connecting mid-run used to make measureLatency throw an uncaught
        // StateError out of this un-awaited loop.
        if (isConnected) return;
        final id = queue.removeAt(0);
        try {
          await measureLatency(id, persist: false, port: portById[id]);
        } catch (_) {
          // measureLatency records its own failure on the node.
        }
      }
    }

    try {
      await Future.wait(List.generate(4, (_) => worker()));
    } finally {
      _measuringAll = false;
      // One write for the whole batch instead of re-encoding the snapshot
      // after every node.
      await _persist();
      notifyListeners();
    }
  }

  Future<void> updateRouting(RoutingSettings value) async {
    if (_tunnelStatus == TunnelStatus.connecting ||
        _tunnelStatus == TunnelStatus.disconnecting) {
      throw StateError('正在切换连接状态，请稍候');
    }
    final wasConnected = _tunnelStatus == TunnelStatus.connected;
    _routing = value;
    await _persist();
    // The routing page is rebuilt with fresh state on save, so report here.
    _lastMessage = wasConnected ? '路由设置已保存，正在重新连接' : '路由设置已保存';
    notifyListeners();
    // Apply immediately instead of making the user disconnect first.
    if (wasConnected) await _restartTunnel();
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

  Future<List<int>> _freePorts(int count) async {
    final response = await _bridge.invoke('getFreePorts', {'count': count});
    response.requireSuccess();
    final ports = ((response.data! as Map)['ports'] as List)
        .map((port) => (port as num).toInt())
        .toList();
    if (ports.isEmpty) throw const XrayException('没有可用的本地端口');
    return ports;
  }

  void _setBusy(bool value) {
    if (value) {
      _busyCount++;
    } else if (_busyCount > 0) {
      _busyCount--;
    }
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
        _disconnectFallback?.cancel();
        _tunnelStatus = TunnelStatus.disconnected;
        _lastMessage = '连接已断开';
      case 'error':
        _tunnelStatus = TunnelStatus.error;
        _lastMessage = event.message ?? 'VPN 原生服务失败';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disconnectFallback?.cancel();
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
