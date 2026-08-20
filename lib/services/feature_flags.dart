import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'cloud_backend_service.dart';

/// Remote feature availability with an offline-first posture.
///
/// Flags are fetched best-effort from the backend's `app_flags` table and
/// cached locally. Reads are synchronous against the cached map, so gating a
/// feature on a flag never blocks the UI and never adds a network
/// dependency: a device that cannot reach the backend keeps the last value
/// it saw, and a device that has never reached it uses the caller's
/// fallback. This makes the table a kill switch, not a launch gate.
class FeatureFlags {
  /// Shared instance so every gate site reads one cached map.
  static final FeatureFlags shared = FeatureFlags();

  FeatureFlags({SharedPreferences? preferences}) : _preferences = preferences;

  static const String storageKey = 'parkiwell_feature_flags_v1';

  /// The motion coach kill switch.
  static const String motionCoachKey = 'motion_coach';

  final AppLogger _logger = AppLogger();
  SharedPreferences? _preferences;
  Map<String, bool> _flags = const <String, bool>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Last known value for [key]; [fallback] when the flag has never been
  /// fetched. Callers should default to enabled so the flag can only turn a
  /// broken feature off, never strand a healthy one.
  bool isEnabled(String key, {bool fallback = true}) => _flags[key] ?? fallback;

  /// Hydrate the cached map from local storage.
  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences preferences = await _resolve();
    final String? raw = preferences.getString(storageKey);
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          _flags = <String, bool>{
            for (final MapEntry<String, Object?> entry in decoded.entries)
              if (entry.value is bool) entry.key: entry.value! as bool,
          };
        }
      } catch (error, stackTrace) {
        // A corrupt cache reads as "never fetched"; callers keep fallbacks.
        _logger.warning('Feature flag cache unreadable', error, stackTrace);
      }
    }
    _loaded = true;
  }

  /// Fetch current flags and update the cache. Best-effort: any failure
  /// keeps the previously cached values.
  Future<void> refresh(CloudBackendService cloud) async {
    await load();
    final Map<String, bool>? fetched = await cloud.fetchAppFlags();
    if (fetched == null) return;
    _flags = Map<String, bool>.unmodifiable(fetched);
    final SharedPreferences preferences = await _resolve();
    await preferences.setString(storageKey, jsonEncode(_flags));
  }

  Future<SharedPreferences> _resolve() async =>
      _preferences ??= await SharedPreferences.getInstance();
}
