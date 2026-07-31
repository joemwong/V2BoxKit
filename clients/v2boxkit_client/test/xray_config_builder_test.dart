import 'package:flutter_test/flutter_test.dart';
import 'package:v2boxkit_client/src/model/models.dart';
import 'package:v2boxkit_client/src/services/xray_config_builder.dart';

void main() {
  const builder = XrayConfigBuilder();
  final base = <String, Object?>{
    'outbounds': [
      <String, Object?>{
        'tag': 'generated',
        'protocol': 'vless',
        'settings': <String, Object?>{},
      },
    ],
  };

  test('builds rule routing, private bypass and authenticated sharing', () {
    const settings = RoutingSettings(
      dnsServer: 'https://1.1.1.1/dns-query',
      mtu: 1400,
      directDomains: ['example.cn'],
      customRules: [
        RoutingRule(
          id: 'block-ads',
          name: 'Block ads',
          kind: RoutingRuleKind.domain,
          action: RoutingRuleAction.block,
          values: ['ads.example'],
        ),
      ],
      localSharing: LocalSharingSettings(
        isEnabled: true,
        listenAddress: '0.0.0.0',
        username: 'user',
        password: 'pass',
      ),
    );

    final config = builder.build(base, settings);
    final outbounds = (config['outbounds']! as List).cast<Map>();
    final inbounds = (config['inbounds']! as List).cast<Map>();
    final routing = config['routing']! as Map;
    final rules = (routing['rules']! as List).cast<Map>();

    expect(outbounds.map((outbound) => outbound['tag']), [
      'proxy',
      'direct',
      'block',
    ]);
    expect(inbounds.map((inbound) => inbound['tag']), [
      'tun-in',
      'local-socks-in',
      'local-http-in',
    ]);
    expect((inbounds.first['settings'] as Map)['mtu'], 1400);
    expect(
      rules.any(
        (rule) =>
            rule['outboundTag'] == 'block' &&
            (rule['domain'] as List).contains('domain:ads.example'),
      ),
      isTrue,
    );
    expect(
      rules.any(
        (rule) =>
            rule['outboundTag'] == 'direct' &&
            rule['ip'] is List &&
            (rule['ip'] as List).contains('192.168.0.0/16'),
      ),
      isTrue,
    );
  });

  test('direct mode sends all TCP and UDP traffic directly', () {
    final config = builder.build(
      base,
      const RoutingSettings(mode: RoutingMode.direct),
    );
    final rules = ((config['routing']! as Map)['rules']! as List).cast<Map>();

    expect(rules, hasLength(1));
    expect(rules.single['network'], 'tcp,udp');
    expect(rules.single['outboundTag'], 'direct');
  });

  test('rejects unauthenticated local sharing', () {
    expect(
      () => builder.build(
        base,
        const RoutingSettings(
          localSharing: LocalSharingSettings(isEnabled: true),
        ),
      ),
      throwsFormatException,
    );
  });

  test('removes libXray outbound name metadata from runtime config', () {
    final namedBase = <String, Object?>{
      'outbounds': [
        <String, Object?>{
          'tag': 'generated',
          'sendThrough': 'Node A',
          'protocol': 'vless',
          'settings': <String, Object?>{},
        },
        <String, Object?>{
          'tag': 'generated-2',
          'sendThrough': 'Node B',
          'protocol': 'shadowsocks',
          'settings': <String, Object?>{},
        },
      ],
    };

    final config = builder.build(namedBase, const RoutingSettings());
    final outbounds = (config['outbounds']! as List).cast<Map>();

    expect(
      outbounds.take(2).every((item) => !item.containsKey('sendThrough')),
      isTrue,
    );
    expect(outbounds.map((outbound) => outbound['tag']), [
      'proxy',
      'generated-2',
      'direct',
      'block',
    ]);
    expect(
      (((namedBase['outbounds']! as List).first as Map)['sendThrough']),
      'Node A',
    );
    expect(
      (((namedBase['outbounds']! as List)[1] as Map)['sendThrough']),
      'Node B',
    );
  });

  test('does not mutate the generated base configuration', () {
    builder.build(base, const RoutingSettings());

    expect((base['outbounds']! as List), hasLength(1));
    expect(((base['outbounds']! as List).single as Map)['tag'], 'generated');
  });
}
