import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

class XrayInvokeResponse {
  const XrayInvokeResponse({required this.success, this.data, this.error = ''});

  final bool success;
  final Object? data;
  final String error;

  factory XrayInvokeResponse.fromJson(Map<String, Object?> json) {
    return XrayInvokeResponse(
      success: json['success'] as bool? ?? false,
      data: json['data'],
      error: json['error'] as String? ?? '',
    );
  }

  void requireSuccess() {
    if (!success) {
      throw XrayException(error.isEmpty ? 'Xray 调用失败' : error);
    }
  }
}

class XrayException implements Exception {
  const XrayException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TunnelOptions {
  const TunnelOptions({required this.mtu, required this.dnsServer});

  final int mtu;
  final String dnsServer;

  Map<String, Object?> toJson() => {'mtu': mtu, 'dnsServer': dnsServer};
}

class TunnelEvent {
  const TunnelEvent(this.status, {this.message});

  final String status;
  final String? message;

  factory TunnelEvent.fromObject(Object? value) {
    if (value is String) return TunnelEvent(value);
    if (value is Map) {
      return TunnelEvent(
        value['status']?.toString() ?? 'unknown',
        message: value['message']?.toString(),
      );
    }
    return const TunnelEvent('unknown');
  }
}

abstract class XrayBridge {
  Stream<TunnelEvent> get events;

  Future<XrayInvokeResponse> invoke(
    String method, [
    Map<String, Object?> payload = const {},
  ]);

  Future<bool> requestPermission();

  Future<void> start(String configJson, TunnelOptions options);

  Future<void> stop();

  Future<bool> isRunning();

  void dispose();

  factory XrayBridge.platform() {
    if (Platform.isAndroid) return AndroidXrayBridge();
    if (Platform.isWindows) return WindowsXrayBridge();
    throw UnsupportedError('V2BoxKit currently supports Android and Windows');
  }
}

class AndroidXrayBridge implements XrayBridge {
  static const _methods = MethodChannel('net.v2boxkit/tunnel');
  static const _events = EventChannel('net.v2boxkit/tunnel-events');

  late final Stream<TunnelEvent> _eventStream = _events
      .receiveBroadcastStream()
      .map(TunnelEvent.fromObject)
      .asBroadcastStream();

  @override
  Stream<TunnelEvent> get events => _eventStream;

  @override
  Future<XrayInvokeResponse> invoke(
    String method, [
    Map<String, Object?> payload = const {},
  ]) async {
    final raw = await _methods.invokeMethod<Object?>('invoke', {
      'method': method,
      'payload': payload,
    });
    if (raw is! Map) {
      throw const XrayException('Android 原生层返回了无效结果');
    }
    return XrayInvokeResponse.fromJson(raw.cast<String, Object?>());
  }

  @override
  Future<bool> requestPermission() async {
    return await _methods.invokeMethod<bool>('prepare') ?? false;
  }

  @override
  Future<void> start(String configJson, TunnelOptions options) async {
    await _methods.invokeMethod<void>('start', {
      'config': configJson,
      ...options.toJson(),
    });
  }

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<bool> isRunning() async {
    return await _methods.invokeMethod<bool>('isRunning') ?? false;
  }

  @override
  void dispose() {}
}

typedef _InvokeNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _InvokeDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class _NativeXray {
  _NativeXray() {
    final library = DynamicLibrary.open('libXray.dll');
    _invoke = library.lookupFunction<_InvokeNative, _InvokeDart>('CGoInvoke');
    _free = library.lookupFunction<_FreeNative, _FreeDart>('CGoFree');
  }

  late final _InvokeDart _invoke;
  late final _FreeDart _free;

  XrayInvokeResponse call(
    String method, [
    Map<String, Object?> payload = const {},
  ]) {
    final request = jsonEncode({
      'apiVersion': 1,
      'method': method,
      'payload': payload,
    });
    final requestPointer = request.toNativeUtf8();
    Pointer<Utf8> responsePointer = nullptr;
    try {
      responsePointer = _invoke(requestPointer);
      if (responsePointer == nullptr) {
        throw const XrayException('libXray 返回了空指针');
      }
      final decoded = jsonDecode(responsePointer.toDartString());
      if (decoded is! Map) {
        throw const XrayException('libXray 返回了无效 JSON');
      }
      return XrayInvokeResponse.fromJson(decoded.cast<String, Object?>());
    } finally {
      malloc.free(requestPointer);
      if (responsePointer != nullptr) _free(responsePointer);
    }
  }
}

class WindowsXrayBridge implements XrayBridge {
  final StreamController<TunnelEvent> _events =
      StreamController<TunnelEvent>.broadcast();
  _NativeXray? _native;

  _NativeXray get _runtime {
    try {
      return _native ??= _NativeXray();
    } on ArgumentError catch (error) {
      throw XrayException(
        '找不到 libXray.dll。请先运行 tool/fetch_windows_runtime.ps1：$error',
      );
    }
  }

  @override
  Stream<TunnelEvent> get events => _events.stream;

  @override
  Future<XrayInvokeResponse> invoke(
    String method, [
    Map<String, Object?> payload = const {},
  ]) async {
    return _runtime.call(method, payload);
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start(String configJson, TunnelOptions options) async {
    _events.add(const TunnelEvent('connecting'));
    try {
      final response = _runtime.call('runXrayFromJson', {
        'configJSON': configJson,
      });
      response.requireSuccess();
      _events.add(const TunnelEvent('connected'));
    } catch (error) {
      _events.add(TunnelEvent('error', message: error.toString()));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _events.add(const TunnelEvent('disconnecting'));
    final response = _runtime.call('stopXray');
    response.requireSuccess();
    _events.add(const TunnelEvent('disconnected'));
  }

  @override
  Future<bool> isRunning() async {
    try {
      final response = _runtime.call('getXrayState');
      if (!response.success || response.data is! Map) return false;
      return (response.data! as Map)['running'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _events.close();
  }
}
