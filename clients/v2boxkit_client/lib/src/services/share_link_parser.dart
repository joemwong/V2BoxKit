import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../model/models.dart';

class ShareLinkParser {
  ShareLinkParser({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const supportedPrefixes = <String>[
    'vless://',
    'vmess://',
    'trojan://',
    'ss://',
    'hysteria2://',
    'hy2://',
  ];

  final Uuid _uuid;

  List<ProxyNode> parseMany(
    String input, {
    String? sourceId,
    String groupName = '手动导入',
  }) {
    final normalized = _decodeSubscriptionIfNeeded(input);
    final nodes = <ProxyNode>[];
    for (final rawLine in const LineSplitter().convert(normalized)) {
      final line = rawLine.trim();
      if (!supportedPrefixes.any(
        (prefix) => line.toLowerCase().startsWith(prefix),
      )) {
        continue;
      }
      try {
        nodes.add(parse(line, sourceId: sourceId, groupName: groupName));
      } on FormatException {
        // A subscription can contain unsupported or malformed entries.
      }
    }
    if (nodes.isEmpty) {
      throw const FormatException('没有找到可用的节点链接');
    }
    return nodes;
  }

  ProxyNode parse(String input, {String? sourceId, String groupName = '手动导入'}) {
    final rawUri = input.trim();
    final scheme = rawUri.split(':').first.toLowerCase();
    return switch (scheme) {
      'vmess' => _parseVmess(rawUri, sourceId, groupName),
      'vless' => _parseUrl(rawUri, ProxyKind.vless, sourceId, groupName),
      'trojan' => _parseUrl(rawUri, ProxyKind.trojan, sourceId, groupName),
      'ss' => _parseShadowsocks(rawUri, sourceId, groupName),
      'hysteria2' ||
      'hy2' => _parseUrl(rawUri, ProxyKind.hysteria2, sourceId, groupName),
      _ => throw const FormatException('暂不支持这个分享链接协议'),
    };
  }

  String normalizeRuntimeUri(String input) {
    final rawUri = input.trim();
    final separator = rawUri.indexOf('://');
    if (separator <= 0) return rawUri;

    final scheme = rawUri.substring(0, separator).toLowerCase();
    final normalized = '$scheme://${rawUri.substring(separator + 3)}'
        .replaceAll('&amp;', '&');
    return switch (scheme) {
      'vmess' => _normalizeLegacyVmess(normalized),
      'ss' => _normalizeLegacyShadowsocks(normalized),
      _ => normalized,
    };
  }

  String _normalizeLegacyVmess(String rawUri) {
    final body = rawUri.substring('vmess://'.length);
    final fragmentIndex = body.indexOf('#');
    if (fragmentIndex < 0) return rawUri;

    final payload = body.substring(0, fragmentIndex);
    final decoded = _decodeBase64(Uri.decodeComponent(payload));
    if (decoded == null) return rawUri;
    try {
      final object = jsonDecode(decoded);
      if (object is Map && object['add'] != null && object['id'] != null) {
        // libXray treats the fragment as part of the legacy Base64 payload.
        // The display name is already stored on ProxyNode, so omit it here.
        return 'vmess://$payload';
      }
    } on FormatException {
      return rawUri;
    }
    return rawUri;
  }

  String _normalizeLegacyShadowsocks(String rawUri) {
    final body = rawUri.substring('ss://'.length);
    final fragmentIndex = body.indexOf('#');
    final payload = fragmentIndex < 0 ? body : body.substring(0, fragmentIndex);
    if (payload.contains('@')) return rawUri;

    final decoded = _decodeBase64(Uri.decodeComponent(payload));
    if (decoded == null) return rawUri;
    final at = decoded.lastIndexOf('@');
    if (at <= 0 || at == decoded.length - 1) return rawUri;
    final credentials = decoded.substring(0, at);
    final credentialSeparator = credentials.indexOf(':');
    if (credentialSeparator <= 0) return rawUri;

    final method = credentials.substring(0, credentialSeparator);
    final password = credentials.substring(credentialSeparator + 1);
    final endpoint = Uri.tryParse(
      'ss://placeholder@${decoded.substring(at + 1)}',
    );
    if (endpoint == null ||
        endpoint.host.isEmpty ||
        !_isValidPort(endpoint.port)) {
      return rawUri;
    }

    final host = endpoint.host.contains(':')
        ? '[${endpoint.host}]'
        : endpoint.host;
    final userInfo =
        '${Uri.encodeComponent(method)}:'
        '${Uri.encodeComponent(password)}';
    final fragment = fragmentIndex < 0 ? '' : body.substring(fragmentIndex);
    return 'ss://$userInfo@$host:${endpoint.port}$fragment';
  }

  ProxyNode _parseVmess(String rawUri, String? sourceId, String groupName) {
    final payload = rawUri.substring('vmess://'.length).split('#').first;
    final decoded = _decodeBase64(payload);
    if (decoded != null) {
      try {
        final object = jsonDecode(decoded);
        if (object is Map) {
          final host = object['add']?.toString().trim() ?? '';
          final port = int.tryParse(object['port']?.toString() ?? '');
          if (host.isNotEmpty && _isValidPort(port)) {
            final name = object['ps']?.toString().trim();
            return _node(
              rawUri: rawUri,
              name: name == null || name.isEmpty ? host : name,
              kind: ProxyKind.vmess,
              host: host,
              port: port!,
              sourceId: sourceId,
              groupName: groupName,
            );
          }
        }
      } on FormatException {
        // Fall through to the modern URL form.
      }
    }
    return _parseUrl(rawUri, ProxyKind.vmess, sourceId, groupName);
  }

  ProxyNode _parseShadowsocks(
    String rawUri,
    String? sourceId,
    String groupName,
  ) {
    try {
      return _parseUrl(rawUri, ProxyKind.shadowsocks, sourceId, groupName);
    } on FormatException {
      final payload = rawUri.substring('ss://'.length).split('#').first;
      final decoded = _decodeBase64(payload);
      if (decoded == null) rethrow;
      final at = decoded.lastIndexOf('@');
      final colon = decoded.lastIndexOf(':');
      if (at < 0 || colon <= at || colon == decoded.length - 1) rethrow;
      final host = decoded.substring(at + 1, colon);
      final port = int.tryParse(decoded.substring(colon + 1));
      if (host.isEmpty || !_isValidPort(port)) rethrow;
      final uri = Uri.tryParse(rawUri);
      return _node(
        rawUri: rawUri,
        name: _fragmentName(uri) ?? host,
        kind: ProxyKind.shadowsocks,
        host: host,
        port: port!,
        sourceId: sourceId,
        groupName: groupName,
      );
    }
  }

  ProxyNode _parseUrl(
    String rawUri,
    ProxyKind kind,
    String? sourceId,
    String groupName,
  ) {
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.host.isEmpty || !_isValidPort(uri.port)) {
      throw const FormatException('分享链接格式不完整');
    }
    return _node(
      rawUri: rawUri,
      name: _fragmentName(uri) ?? uri.host,
      kind: kind,
      host: uri.host,
      port: uri.port,
      sourceId: sourceId,
      groupName: groupName,
    );
  }

  ProxyNode _node({
    required String rawUri,
    required String name,
    required ProxyKind kind,
    required String host,
    required int port,
    required String? sourceId,
    required String groupName,
  }) {
    return ProxyNode(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      host: host,
      port: port,
      rawUri: rawUri,
      sourceId: sourceId,
      groupName: groupName,
    );
  }

  String _decodeSubscriptionIfNeeded(String input) {
    final trimmed = input.trim();
    if (supportedPrefixes.any(
      (prefix) => trimmed.toLowerCase().contains(prefix),
    )) {
      return trimmed;
    }
    return _decodeBase64(trimmed) ?? trimmed;
  }

  String? _decodeBase64(String value) {
    var normalized = value
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll(RegExp(r'\s'), '');
    normalized += '=' * ((4 - normalized.length % 4) % 4);
    try {
      return utf8.decode(base64Decode(normalized));
    } on FormatException {
      return null;
    }
  }

  String? _fragmentName(Uri? uri) {
    final fragment = uri?.fragment.trim();
    return fragment == null || fragment.isEmpty
        ? null
        : Uri.decodeComponent(fragment);
  }

  bool _isValidPort(int? port) => port != null && port >= 1 && port <= 65535;
}
