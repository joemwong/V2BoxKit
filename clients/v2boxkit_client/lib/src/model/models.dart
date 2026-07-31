enum ProxyKind {
  vless,
  vmess,
  trojan,
  shadowsocks,
  hysteria2;

  String get wireName => switch (this) {
    ProxyKind.shadowsocks => 'ss',
    _ => name,
  };

  String get displayName => switch (this) {
    ProxyKind.vless => 'VLESS',
    ProxyKind.vmess => 'VMess',
    ProxyKind.trojan => 'Trojan',
    ProxyKind.shadowsocks => 'Shadowsocks',
    ProxyKind.hysteria2 => 'Hysteria 2',
  };

  static ProxyKind fromWireName(String value) => switch (value) {
    'vless' => ProxyKind.vless,
    'vmess' => ProxyKind.vmess,
    'trojan' => ProxyKind.trojan,
    'ss' || 'shadowsocks' => ProxyKind.shadowsocks,
    'hysteria2' || 'hy2' => ProxyKind.hysteria2,
    _ => throw FormatException('Unsupported proxy protocol: $value'),
  };
}

class ProxyNode {
  const ProxyNode({
    required this.id,
    required this.name,
    required this.kind,
    required this.host,
    required this.port,
    required this.rawUri,
    this.sourceId,
    this.groupName = '手动导入',
    this.isFavorite = false,
    this.isPinned = false,
    this.latencyMilliseconds,
    this.latencyMeasuredAt,
  });

  final String id;
  final String name;
  final ProxyKind kind;
  final String host;
  final int port;
  final String rawUri;
  final String? sourceId;
  final String groupName;
  final bool isFavorite;
  final bool isPinned;
  final int? latencyMilliseconds;
  final DateTime? latencyMeasuredAt;

  String get endpoint => '$host:$port';
  String get latencyText {
    final value = latencyMilliseconds;
    if (value == null) return '—';
    if (value >= 10000) return '失败';
    return '$value ms';
  }

  ProxyNode copyWith({
    String? id,
    String? name,
    ProxyKind? kind,
    String? host,
    int? port,
    String? rawUri,
    String? sourceId,
    bool clearSourceId = false,
    String? groupName,
    bool? isFavorite,
    bool? isPinned,
    int? latencyMilliseconds,
    bool clearLatency = false,
    DateTime? latencyMeasuredAt,
  }) {
    return ProxyNode(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      host: host ?? this.host,
      port: port ?? this.port,
      rawUri: rawUri ?? this.rawUri,
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
      groupName: groupName ?? this.groupName,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      latencyMilliseconds: clearLatency
          ? null
          : (latencyMilliseconds ?? this.latencyMilliseconds),
      latencyMeasuredAt: clearLatency
          ? null
          : (latencyMeasuredAt ?? this.latencyMeasuredAt),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.wireName,
    'host': host,
    'port': port,
    'rawUri': rawUri,
    'sourceId': sourceId,
    'groupName': groupName,
    'isFavorite': isFavorite,
    'isPinned': isPinned,
    'latencyMilliseconds': latencyMilliseconds,
    'latencyMeasuredAt': latencyMeasuredAt?.toIso8601String(),
  };

  factory ProxyNode.fromJson(Map<String, Object?> json) => ProxyNode(
    id: json['id']! as String,
    name: json['name']! as String,
    kind: ProxyKind.fromWireName(json['kind']! as String),
    host: json['host']! as String,
    port: (json['port']! as num).toInt(),
    rawUri: json['rawUri']! as String,
    sourceId: json['sourceId'] as String?,
    groupName: json['groupName'] as String? ?? '手动导入',
    isFavorite: json['isFavorite'] as bool? ?? false,
    isPinned: json['isPinned'] as bool? ?? false,
    latencyMilliseconds: (json['latencyMilliseconds'] as num?)?.toInt(),
    latencyMeasuredAt: json['latencyMeasuredAt'] == null
        ? null
        : DateTime.tryParse(json['latencyMeasuredAt']! as String),
  );
}

class ProxySubscription {
  const ProxySubscription({
    required this.id,
    required this.name,
    required this.url,
    this.refreshHours = 24,
    this.lastUpdatedAt,
    this.etag,
    this.lastModified,
    this.lastError,
  });

  final String id;
  final String name;
  final Uri url;
  final int refreshHours;
  final DateTime? lastUpdatedAt;
  final String? etag;
  final String? lastModified;
  final String? lastError;

  bool isDue(DateTime now) {
    final updatedAt = lastUpdatedAt;
    return updatedAt == null ||
        now.difference(updatedAt) >= Duration(hours: refreshHours);
  }

  ProxySubscription copyWith({
    String? name,
    Uri? url,
    int? refreshHours,
    DateTime? lastUpdatedAt,
    String? etag,
    String? lastModified,
    String? lastError,
    bool clearError = false,
  }) {
    return ProxySubscription(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      refreshHours: refreshHours ?? this.refreshHours,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url.toString(),
    'refreshHours': refreshHours,
    'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
    'etag': etag,
    'lastModified': lastModified,
    'lastError': lastError,
  };

  factory ProxySubscription.fromJson(Map<String, Object?> json) =>
      ProxySubscription(
        id: json['id']! as String,
        name: json['name']! as String,
        url: Uri.parse(json['url']! as String),
        refreshHours: (json['refreshHours'] as num?)?.toInt() ?? 24,
        lastUpdatedAt: json['lastUpdatedAt'] == null
            ? null
            : DateTime.tryParse(json['lastUpdatedAt']! as String),
        etag: json['etag'] as String?,
        lastModified: json['lastModified'] as String?,
        lastError: json['lastError'] as String?,
      );
}

enum RoutingMode {
  rule,
  global,
  direct;

  String get label => switch (this) {
    RoutingMode.rule => '规则',
    RoutingMode.global => '全局',
    RoutingMode.direct => '直连',
  };
}

enum RoutingRuleKind {
  domain,
  ip;

  String get label => this == domain ? '域名' : 'IP/CIDR';
}

enum RoutingRuleAction {
  proxy,
  direct,
  block;

  String get label => switch (this) {
    RoutingRuleAction.proxy => '代理',
    RoutingRuleAction.direct => '直连',
    RoutingRuleAction.block => '拦截',
  };
}

class RoutingRule {
  const RoutingRule({
    required this.id,
    required this.name,
    required this.kind,
    required this.action,
    required this.values,
    this.isEnabled = true,
  });

  final String id;
  final String name;
  final RoutingRuleKind kind;
  final RoutingRuleAction action;
  final List<String> values;
  final bool isEnabled;

  List<String> get normalizedValues => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  RoutingRule copyWith({bool? isEnabled}) => RoutingRule(
    id: id,
    name: name,
    kind: kind,
    action: action,
    values: values,
    isEnabled: isEnabled ?? this.isEnabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'action': action.name,
    'values': values,
    'isEnabled': isEnabled,
  };

  factory RoutingRule.fromJson(Map<String, Object?> json) => RoutingRule(
    id: json['id']! as String,
    name: json['name']! as String,
    kind: RoutingRuleKind.values.byName(json['kind']! as String),
    action: RoutingRuleAction.values.byName(json['action']! as String),
    values: (json['values']! as List).cast<String>(),
    isEnabled: json['isEnabled'] as bool? ?? true,
  );
}

class LocalSharingSettings {
  const LocalSharingSettings({
    this.isEnabled = false,
    this.listenAddress = '127.0.0.1',
    this.socksPort = 10808,
    this.httpPort = 10809,
    this.username = '',
    this.password = '',
  });

  final bool isEnabled;
  final String listenAddress;
  final int socksPort;
  final int httpPort;
  final String username;
  final String password;

  bool get isValid =>
      !isEnabled ||
      (username.isNotEmpty &&
          password.isNotEmpty &&
          socksPort > 0 &&
          socksPort <= 65535 &&
          httpPort > 0 &&
          httpPort <= 65535);

  LocalSharingSettings copyWith({
    bool? isEnabled,
    String? listenAddress,
    int? socksPort,
    int? httpPort,
    String? username,
    String? password,
  }) {
    return LocalSharingSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      listenAddress: listenAddress ?? this.listenAddress,
      socksPort: socksPort ?? this.socksPort,
      httpPort: httpPort ?? this.httpPort,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, Object?> toJson() => {
    'isEnabled': isEnabled,
    'listenAddress': listenAddress,
    'socksPort': socksPort,
    'httpPort': httpPort,
    'username': username,
    'password': password,
  };

  factory LocalSharingSettings.fromJson(Map<String, Object?> json) =>
      LocalSharingSettings(
        isEnabled: json['isEnabled'] as bool? ?? false,
        listenAddress: json['listenAddress'] as String? ?? '127.0.0.1',
        socksPort: (json['socksPort'] as num?)?.toInt() ?? 10808,
        httpPort: (json['httpPort'] as num?)?.toInt() ?? 10809,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );
}

class RoutingSettings {
  const RoutingSettings({
    this.mode = RoutingMode.rule,
    this.directDomains = const [],
    this.customRules = const [],
    this.bypassPrivateNetworks = true,
    this.dnsServer = '1.1.1.1',
    this.mtu = 1500,
    this.localSharing = const LocalSharingSettings(),
  });

  final RoutingMode mode;
  final List<String> directDomains;
  final List<RoutingRule> customRules;
  final bool bypassPrivateNetworks;
  final String dnsServer;
  final int mtu;
  final LocalSharingSettings localSharing;

  RoutingSettings copyWith({
    RoutingMode? mode,
    List<String>? directDomains,
    List<RoutingRule>? customRules,
    bool? bypassPrivateNetworks,
    String? dnsServer,
    int? mtu,
    LocalSharingSettings? localSharing,
  }) {
    return RoutingSettings(
      mode: mode ?? this.mode,
      directDomains: directDomains ?? this.directDomains,
      customRules: customRules ?? this.customRules,
      bypassPrivateNetworks:
          bypassPrivateNetworks ?? this.bypassPrivateNetworks,
      dnsServer: dnsServer ?? this.dnsServer,
      mtu: mtu ?? this.mtu,
      localSharing: localSharing ?? this.localSharing,
    );
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'directDomains': directDomains,
    'customRules': customRules.map((rule) => rule.toJson()).toList(),
    'bypassPrivateNetworks': bypassPrivateNetworks,
    'dnsServer': dnsServer,
    'mtu': mtu,
    'localSharing': localSharing.toJson(),
  };

  factory RoutingSettings.fromJson(
    Map<String, Object?> json,
  ) => RoutingSettings(
    mode: RoutingMode.values.byName(json['mode'] as String? ?? 'rule'),
    directDomains: (json['directDomains'] as List?)?.cast<String>() ?? const [],
    customRules:
        (json['customRules'] as List?)
            ?.map(
              (rule) =>
                  RoutingRule.fromJson((rule as Map).cast<String, Object?>()),
            )
            .toList() ??
        const [],
    bypassPrivateNetworks: json['bypassPrivateNetworks'] as bool? ?? true,
    dnsServer: json['dnsServer'] as String? ?? '1.1.1.1',
    mtu: (json['mtu'] as num?)?.toInt() ?? 1500,
    localSharing: json['localSharing'] == null
        ? const LocalSharingSettings()
        : LocalSharingSettings.fromJson(
            (json['localSharing'] as Map).cast<String, Object?>(),
          ),
  );
}

class AppSnapshot {
  const AppSnapshot({
    this.formatVersion = 1,
    this.nodes = const [],
    this.subscriptions = const [],
    this.routing = const RoutingSettings(),
    this.selectedNodeId,
  });

  final int formatVersion;
  final List<ProxyNode> nodes;
  final List<ProxySubscription> subscriptions;
  final RoutingSettings routing;
  final String? selectedNodeId;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'subscriptions': subscriptions
        .map((subscription) => subscription.toJson())
        .toList(),
    'routing': routing.toJson(),
    'selectedNodeId': selectedNodeId,
  };

  factory AppSnapshot.fromJson(Map<String, Object?> json) {
    final version = (json['formatVersion'] as num?)?.toInt() ?? 1;
    if (version != 1) {
      throw const FormatException('不支持的备份版本');
    }
    return AppSnapshot(
      formatVersion: version,
      nodes:
          (json['nodes'] as List?)
              ?.map(
                (node) =>
                    ProxyNode.fromJson((node as Map).cast<String, Object?>()),
              )
              .toList() ??
          const [],
      subscriptions:
          (json['subscriptions'] as List?)
              ?.map(
                (subscription) => ProxySubscription.fromJson(
                  (subscription as Map).cast<String, Object?>(),
                ),
              )
              .toList() ??
          const [],
      routing: json['routing'] == null
          ? const RoutingSettings()
          : RoutingSettings.fromJson(
              (json['routing'] as Map).cast<String, Object?>(),
            ),
      selectedNodeId: json['selectedNodeId'] as String?,
    );
  }
}

enum TunnelStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error;

  String get label => switch (this) {
    TunnelStatus.disconnected => '未连接',
    TunnelStatus.connecting => '连接中',
    TunnelStatus.connected => '已连接',
    TunnelStatus.disconnecting => '断开中',
    TunnelStatus.error => '连接失败',
  };
}
