import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/models.dart';

class StorageService {
  static const _snapshotKey = 'v2boxkit.snapshot.v1';
  static const _backupType = XTypeGroup(
    label: 'V2BoxKit backup',
    extensions: ['v2boxkit'],
    mimeTypes: ['application/json'],
  );

  Future<AppSnapshot> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_snapshotKey);
    if (value == null || value.isEmpty) return const AppSnapshot();
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('本地配置格式错误');
    return AppSnapshot.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> save(AppSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_snapshotKey, encode(snapshot));
  }

  String encode(AppSnapshot snapshot) {
    return const JsonEncoder.withIndent('  ').convert(snapshot.toJson());
  }

  AppSnapshot decode(String content) {
    if (utf8.encode(content).length > 16 * 1024 * 1024) {
      throw const FormatException('备份文件超过 16 MiB 限制');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) throw const FormatException('备份文件格式错误');
    return AppSnapshot.fromJson(decoded.cast<String, Object?>());
  }

  Future<String?> exportBackup(AppSnapshot snapshot) async {
    final location = await getSaveLocation(
      suggestedName: 'V2BoxKit-${_dateStamp()}.v2boxkit',
      acceptedTypeGroups: const [_backupType],
    );
    if (location == null) return null;
    final data = Uint8List.fromList(utf8.encode(encode(snapshot)));
    final file = XFile.fromData(
      data,
      mimeType: 'application/json',
      name: 'V2BoxKit-${_dateStamp()}.v2boxkit',
    );
    await file.saveTo(location.path);
    return location.path;
  }

  Future<AppSnapshot?> importBackup() async {
    final file = await openFile(acceptedTypeGroups: const [_backupType]);
    if (file == null) return null;
    return decode(await file.readAsString());
  }

  String _dateStamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
  }
}
