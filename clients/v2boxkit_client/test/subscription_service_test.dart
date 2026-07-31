import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:v2boxkit_client/src/model/models.dart';
import 'package:v2boxkit_client/src/services/subscription_service.dart';

void main() {
  test('uses conditional headers and preserves validators on 304', () async {
    final client = MockClient((request) async {
      expect(request.headers['if-none-match'], '"version-1"');
      expect(
        request.headers['if-modified-since'],
        'Wed, 01 Jul 2026 00:00:00 GMT',
      );
      expect(request.headers['user-agent'], 'V2BoxKit/1.0');
      return http.Response('', 304, headers: {'etag': '"version-2"'});
    });
    final service = SubscriptionService(client: client);
    const modified = 'Wed, 01 Jul 2026 00:00:00 GMT';
    final subscription = ProxySubscription(
      id: 'subscription-1',
      name: 'Example',
      url: Uri.parse('https://example.com/subscription'),
      etag: '"version-1"',
      lastModified: modified,
    );

    final result = await service.fetch(subscription);

    expect(result.notModified, isTrue);
    expect(result.etag, '"version-2"');
    expect(result.lastModified, modified);
    service.close();
  });

  test('returns a successful UTF-8 subscription body', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        'vless://id@example.com:443'.codeUnits,
        200,
        headers: {'etag': '"version-1"'},
      ),
    );
    final service = SubscriptionService(client: client);
    final subscription = ProxySubscription(
      id: 'subscription-1',
      name: 'Example',
      url: Uri.parse('https://example.com/subscription'),
    );

    final result = await service.fetch(subscription);

    expect(result.notModified, isFalse);
    expect(result.body, 'vless://id@example.com:443');
    expect(result.etag, '"version-1"');
    service.close();
  });

  test('rejects an insecure subscription before network access', () async {
    final client = MockClient((_) async {
      throw StateError('The client must not be called');
    });
    final service = SubscriptionService(client: client);
    final subscription = ProxySubscription(
      id: 'subscription-1',
      name: 'Example',
      url: Uri.parse('http://example.com/subscription'),
    );

    await expectLater(service.fetch(subscription), throwsFormatException);
    service.close();
  });
}
