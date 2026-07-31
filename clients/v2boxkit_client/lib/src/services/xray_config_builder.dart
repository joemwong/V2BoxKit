import 'dart:convert';
import 'dart:io';

import '../model/models.dart';

class XrayConfigBuilder {
  const XrayConfigBuilder();

  static const _privateNetworks = <String>[
    '0.0.0.0/8',
    '10.0.0.0/8',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '224.0.0.0/4',
    '::1/128',
    'fc00::/7',
    'fe80::/10',
    'ff00::/8',
  ];

  Map<String, Object?> build(
    Map<String, Object?> base,
    RoutingSettings settings,
  ) {
    final configuration = (jsonDecode(jsonEncode(base)) as Map)
        .cast<String, Object?>();
    final rawOutbounds = configuration['outbounds'];
    if (rawOutbounds is! List || rawOutbounds.isEmpty) {
      throw const FormatException('节点没有生成可用的 Xray 出站配置');
    }

    final outbounds = rawOutbounds
        .map((item) => (item as Map).cast<String, Object?>())
        .where((item) => !const {'direct', 'block'}.contains(item['tag']))
        .toList();
    if (outbounds.isEmpty) {
      throw const FormatException('节点没有生成可用的 Xray 出站配置');
    }
    for (final outbound in outbounds) {
      // libXray stores the share-link display name in sendThrough, while
      // Xray-core interprets that field as a source address at runtime.
      outbound.remove('sendThrough');
    }

    outbounds.first['tag'] = 'proxy';
    outbounds.addAll([
      <String, Object?>{'tag': 'direct', 'protocol': 'freedom'},
      <String, Object?>{'tag': 'block', 'protocol': 'blackhole'},
    ]);

    configuration
      ..['log'] = <String, Object?>{'loglevel': 'warning'}
      ..['outbounds'] = outbounds
      ..['inbounds'] = _inbounds(settings)
      ..['dns'] = <String, Object?>{
        'servers': [settings.dnsServer],
        'queryStrategy': 'UseIP',
      }
      ..['routing'] = <String, Object?>{
        'domainStrategy': 'IPIfNonMatch',
        'rules': _routingRules(settings),
      };

    return configuration;
  }

  List<Map<String, Object?>> _inbounds(RoutingSettings settings) {
    final tunSettings = <String, Object?>{
      'name': Platform.isWindows ? 'V2BoxKit' : 'v2boxkit',
      'mtu': settings.mtu,
    };
    if (Platform.isWindows) {
      tunSettings.addAll({
        'desc': 'V2BoxKit',
        'gateway': ['172.19.0.1/30', 'fd00:172:19::1/64'],
        'dns': [_plainDnsAddress(settings.dnsServer)],
        'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
        'autoOutboundsInterface': 'auto',
      });
    }

    final inbounds = <Map<String, Object?>>[
      {
        'tag': 'tun-in',
        'protocol': 'tun',
        'settings': tunSettings,
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
        },
      },
    ];

    final sharing = settings.localSharing;
    if (sharing.isEnabled) {
      if (!sharing.isValid) {
        throw const FormatException('本地代理分享必须设置用户名和密码');
      }
      final accounts = [
        {'user': sharing.username, 'pass': sharing.password},
      ];
      inbounds.addAll([
        {
          'tag': 'local-socks-in',
          'listen': sharing.listenAddress,
          'port': sharing.socksPort,
          'protocol': 'socks',
          'settings': {'auth': 'password', 'accounts': accounts, 'udp': true},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
        {
          'tag': 'local-http-in',
          'listen': sharing.listenAddress,
          'port': sharing.httpPort,
          'protocol': 'http',
          'settings': {'accounts': accounts},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
        },
      ]);
    }
    return inbounds;
  }

  List<Map<String, Object?>> _routingRules(RoutingSettings settings) {
    switch (settings.mode) {
      case RoutingMode.global:
        return const [];
      case RoutingMode.direct:
        return const [
          {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'direct'},
        ];
      case RoutingMode.rule:
        final rules = <Map<String, Object?>>[];
        for (final rule in settings.customRules) {
          final converted = _customRule(rule);
          if (converted != null) rules.add(converted);
        }
        if (settings.bypassPrivateNetworks) {
          rules.add({
            'type': 'field',
            'ip': _privateNetworks,
            'outboundTag': 'direct',
          });
        }
        final domains = settings.directDomains
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty)
            .map(
              (domain) => domain.startsWith(RegExp(r'(domain|full|regexp):'))
                  ? domain
                  : 'domain:$domain',
            )
            .toList();
        if (domains.isNotEmpty) {
          rules.add({
            'type': 'field',
            'domain': domains,
            'outboundTag': 'direct',
          });
        }
        return rules;
    }
  }

  Map<String, Object?>? _customRule(RoutingRule rule) {
    if (!rule.isEnabled || rule.normalizedValues.isEmpty) return null;
    final outboundTag = switch (rule.action) {
      RoutingRuleAction.proxy => 'proxy',
      RoutingRuleAction.direct => 'direct',
      RoutingRuleAction.block => 'block',
    };
    final result = <String, Object?>{
      'type': 'field',
      'outboundTag': outboundTag,
    };
    switch (rule.kind) {
      case RoutingRuleKind.domain:
        result['domain'] = rule.normalizedValues.map((value) {
          final normalized = value.toLowerCase();
          return normalized.startsWith(RegExp(r'(domain|full|regexp):'))
              ? normalized
              : 'domain:$normalized';
        }).toList();
      case RoutingRuleKind.ip:
        result['ip'] = rule.normalizedValues;
    }
    return result;
  }

  String _plainDnsAddress(String value) {
    final normalized = value.trim();
    if (InternetAddress.tryParse(normalized) != null) return normalized;
    final uri = Uri.tryParse(normalized);
    if (uri != null && InternetAddress.tryParse(uri.host) != null) {
      return uri.host;
    }
    return '1.1.1.1';
  }
}
