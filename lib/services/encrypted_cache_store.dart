import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_logger.dart';

/// Encrypts the local health cache at rest.
///
/// Payloads are sealed with AES-256-GCM. The data key is generated on device
/// and lives in the platform keystore (Android Keystore / iOS Keychain) via
/// flutter_secure_storage; only ciphertext reaches SharedPreferences.
class EncryptedCacheStore {
  EncryptedCacheStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _keyName = 'parkiwell_cache_data_key_v1';

  /// Prefix marking encrypted payloads, so legacy plaintext JSON snapshots
  /// can be recognized and migrated on first read.
  static const String payloadPrefix = 'enc.v1:';

  final FlutterSecureStorage _secureStorage;
  final AesGcm _cipher = AesGcm.with256bits();
  final AppLogger _logger = AppLogger();

  SecretKey? _dataKey;
  bool _keystoreUnavailable = false;

  /// True when the platform keystore cannot be reached (for example in unit
  /// tests or on desktop shells without a secure storage implementation).
  bool get keystoreUnavailable => _keystoreUnavailable;

  Future<SecretKey?> _obtainKey() async {
    if (_dataKey != null) return _dataKey;
    if (_keystoreUnavailable) return null;
    try {
      final stored = await _secureStorage.read(key: _keyName);
      if (stored != null && stored.isNotEmpty) {
        _dataKey = SecretKey(base64Decode(stored));
        return _dataKey;
      }
      final rng = Random.secure();
      final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
      await _secureStorage.write(key: _keyName, value: base64Encode(bytes));
      _dataKey = SecretKey(bytes);
      return _dataKey;
    } on MissingPluginException {
      // No keystore in this environment; callers fall back to plaintext and
      // the condition is surfaced through [keystoreUnavailable].
      _keystoreUnavailable = true;
      _logger.warning('Secure keystore unavailable; cache stays unencrypted');
      return null;
    }
  }

  /// Seals [plaintext]; returns the plaintext unchanged when no keystore is
  /// available so data is never lost.
  Future<String> seal(String plaintext) async {
    final key = await _obtainKey();
    if (key == null) return plaintext;
    final box = await _cipher.encrypt(utf8.encode(plaintext), secretKey: key);
    return '$payloadPrefix${base64Encode(box.concatenation())}';
  }

  /// Opens a stored payload. Legacy plaintext payloads are returned as-is;
  /// undecryptable ciphertext returns null.
  Future<String?> open(String stored) async {
    if (!stored.startsWith(payloadPrefix)) return stored;
    final key = await _obtainKey();
    if (key == null) return null;
    try {
      final raw = base64Decode(stored.substring(payloadPrefix.length));
      final box = SecretBox.fromConcatenation(
        raw,
        nonceLength: AesGcm.defaultNonceLength,
        macLength: 16,
      );
      final clear = await _cipher.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (e) {
      _logger.warning('Unable to decrypt local cache payload');
      return null;
    }
  }
}
