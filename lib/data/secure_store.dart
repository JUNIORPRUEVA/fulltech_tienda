import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();

  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
  static final Map<String, String> _memory = <String, String>{};

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static Future<String> readString(String key) async {
    if (_isFlutterTest) return _memory[key] ?? '';
    try {
      return (await _storage.read(key: key)) ?? '';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureStore.readString failed ($key): $e');
      }
      return '';
    }
  }

  static Future<void> writeString(String key, String value) async {
    final v = value.trim();
    if (_isFlutterTest) {
      if (v.isEmpty) {
        _memory.remove(key);
      } else {
        _memory[key] = v;
      }
      return;
    }
    try {
      if (v.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: v);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureStore.writeString failed ($key): $e');
      }
    }
  }

  static Future<void> delete(String key) async {
    if (_isFlutterTest) {
      _memory.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureStore.delete failed ($key): $e');
      }
    }
  }
}

