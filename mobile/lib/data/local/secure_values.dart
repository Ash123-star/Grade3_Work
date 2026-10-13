import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// Values never pass through preferences, diagnostics or business DTOs.
abstract interface class SecureValues {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class PlatformSecureValues implements SecureValues {
  const PlatformSecureValues();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );
  @override
  Future<String?> read(String key) async {
    _checkPlatform();
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) async {
    _checkPlatform();
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> remove(String key) async {
    _checkPlatform();
    await _storage.delete(key: key);
  }

  void _checkPlatform() {
    if (kIsWeb) {
      throw const LocalStorageFailure('浏览器预览只保留当前会话，本机安全存储请使用Android应用');
    }
  }
}

class LocalStorageFailure implements Exception {
  const LocalStorageFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
