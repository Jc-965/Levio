import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences for how live coaching is delivered.
///
/// Spoken cues and haptic taps are delivery channels, not measurements, so
/// they are the person's choice: some find speech during exercise
/// distracting, others rely on it. Large on-screen text always stays on;
/// these toggles never reduce coaching below a visible channel.
class MotionCoachPreferences extends ChangeNotifier {
  MotionCoachPreferences({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String speechKey = 'parkiwell_motion_coach_speech_enabled_v1';
  static const String hapticsKey = 'parkiwell_motion_coach_haptics_enabled_v1';
  static const String syncResultsKey = 'parkiwell_motion_coach_sync_enabled_v1';

  /// Process-wide instance so every screen observes the same toggles.
  static final MotionCoachPreferences shared = MotionCoachPreferences();

  SharedPreferences? _preferences;
  bool _speechEnabled = true;
  bool _hapticsEnabled = true;
  bool _syncResultsEnabled = true;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get speechEnabled => _speechEnabled;
  bool get hapticsEnabled => _hapticsEnabled;

  /// Whether derived session results (scores and repetition counts, never
  /// video or pose data) are backed up to the signed-in account.
  bool get syncResultsEnabled => _syncResultsEnabled;

  Future<void> load() async {
    final SharedPreferences preferences = await _resolve();
    _speechEnabled = preferences.getBool(speechKey) ?? true;
    _hapticsEnabled = preferences.getBool(hapticsKey) ?? true;
    _syncResultsEnabled = preferences.getBool(syncResultsKey) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSpeechEnabled(bool enabled) async {
    if (_speechEnabled == enabled) return;
    _speechEnabled = enabled;
    notifyListeners();
    final SharedPreferences preferences = await _resolve();
    await preferences.setBool(speechKey, enabled);
  }

  Future<void> setHapticsEnabled(bool enabled) async {
    if (_hapticsEnabled == enabled) return;
    _hapticsEnabled = enabled;
    notifyListeners();
    final SharedPreferences preferences = await _resolve();
    await preferences.setBool(hapticsKey, enabled);
  }

  Future<void> setSyncResultsEnabled(bool enabled) async {
    if (_syncResultsEnabled == enabled) return;
    _syncResultsEnabled = enabled;
    notifyListeners();
    final SharedPreferences preferences = await _resolve();
    await preferences.setBool(syncResultsKey, enabled);
  }

  Future<SharedPreferences> _resolve() async =>
      _preferences ??= await SharedPreferences.getInstance();
}
