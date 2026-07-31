import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:v2boxkit_client/src/model/models.dart';
import 'package:v2boxkit_client/src/services/share_link_parser.dart';

void main() {
  group('ShareLinkParser', () {
    final parser = ShareLinkParser();

    test('parses VLESS URL metadata', () {
      final node = parser.parse(
        'vless://00000000-0000-4000-8000-000000000000@example.com:443'
        '?security=tls&type=ws#Tokyo',
      );

      expect(node.kind, ProxyKind.vless);
      expect(node.name, 'Tokyo');
      expect(node.host, 'example.com');
      expect(node.port, 443);
    });

    test('parses legacy VMess and Base64 subscription', () {
      final vmess =
          'vmess://${base64Encode(utf8.encode(jsonEncode({'v': '2', 'ps': 'Singapore', 'add': 'sg.example.com', 'port': '8443', 'id': '00000000-0000-4000-8000-000000000000'})))}';
      final subscription = base64Encode(utf8.encode('$vmess\n'));

      final nodes = parser.parseMany(subscription, sourceId: 'subscription-1');

      expect(nodes, hasLength(1));
      expect(nodes.single.kind, ProxyKind.vmess);
      expect(nodes.single.name, 'Singapore');
      expect(nodes.single.endpoint, 'sg.example.com:8443');
      expect(nodes.single.sourceId, 'subscription-1');
    });
  });

  test('AppSnapshot JSON round trip preserves P1 settings', () {
    final original = AppSnapshot(
      selectedNodeId: 'node-1',
      nodes: const [
        ProxyNode(
          id: 'node-1',
          name: 'Example',
          kind: ProxyKind.trojan,
          host: 'example.com',
          port: 443,
          rawUri: 'trojan://secret@example.com:443',
          isFavorite: true,
        ),
      ],
      routing: const RoutingSettings(
        dnsServer: '9.9.9.9',
        mtu: 1400,
        directDomains: ['example.cn'],
        localSharing: LocalSharingSettings(
          isEnabled: true,
          username: 'user',
          password: 'pass',
        ),
      ),
    );

    final restored = AppSnapshot.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
    );

    expect(restored.selectedNodeId, 'node-1');
    expect(restored.nodes.single.isFavorite, isTrue);
    expect(restored.routing.dnsServer, '9.9.9.9');
    expect(restored.routing.mtu, 1400);
    expect(restored.routing.localSharing.isValid, isTrue);
  });
}
