import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/models.dart';

class SubscriptionFetchResult {
  const SubscriptionFetchResult({
    required this.notModified,
    this.body,
    this.etag,
    this.lastModified,
  });

  final bool notModified;
  final String? body;
  final String? etag;
  final String? lastModified;
}

class SubscriptionService {
  SubscriptionService({http.Client? client})
    : _client = client ?? http.Client();

  static const _maximumBytes = 4 * 1024 * 1024;
  final http.Client _client;

  Future<SubscriptionFetchResult> fetch(ProxySubscription subscription) async {
    if (subscription.url.scheme != 'https') {
      throw const FormatException('订阅地址必须使用 HTTPS');
    }
    final headers = <String, String>{
      'accept': 'text/plain, application/json, application/yaml, */*',
      'user-agent': 'V2BoxKit/1.0',
    };
    if (subscription.etag case final etag?) {
      headers['if-none-match'] = etag;
    }
    if (subscription.lastModified case final modified?) {
      headers['if-modified-since'] = modified;
    }

    final response = await _client
        .get(subscription.url, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 304) {
      return SubscriptionFetchResult(
        notModified: true,
        etag: response.headers['etag'] ?? subscription.etag,
        lastModified:
            response.headers['last-modified'] ?? subscription.lastModified,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        '订阅服务器返回 HTTP ${response.statusCode}',
        subscription.url,
      );
    }
    if (response.bodyBytes.length > _maximumBytes) {
      throw const FormatException('订阅内容超过 4 MiB 限制');
    }
    return SubscriptionFetchResult(
      notModified: false,
      body: utf8.decode(response.bodyBytes, allowMalformed: false),
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
    );
  }

  void close() => _client.close();
}
