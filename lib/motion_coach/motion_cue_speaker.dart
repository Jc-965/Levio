import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract interface class MotionCueSpeaker {
  Future<void> initialize();

  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

/// Best-effort on-device speech for live, allowlisted coaching cues.
///
/// Speech failure never interrupts pose analysis; large text and haptics remain
/// available when a device has no installed voice.
class PlatformMotionCueSpeaker implements MotionCueSpeaker {
  PlatformMotionCueSpeaker({FlutterTts? engine})
    : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;
  Future<void>? _initialization;
  bool _disposed = false;
  bool _speechAvailable = false;

  @override
  Future<void> initialize() => _initialization ??= _configure();

  Future<void> _configure() async {
    try {
      if (kIsWeb) return;
      final Map<String, String>? voice = selectOfflineEnglishVoice(
        await _engine.getVoices,
      );
      if (voice == null) return;
      await _engine.setLanguage('en-US');
      await _engine.setVoice(voice);
      await _engine.setSpeechRate(0.45);
      await _engine.setVolume(1);
      await _engine.setPitch(1);
      await _engine.awaitSpeakCompletion(false);
      _speechAvailable = true;
    } catch (_) {
      // Initialization is best effort; visual and haptic cues remain active.
    }
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed || text.trim().isEmpty) return;
    try {
      await initialize();
      if (_disposed || !_speechAvailable) return;
      await _engine.stop();
      await _engine.speak(text);
    } catch (_) {
      // Text and haptic cues remain available if TTS is unavailable.
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    try {
      await _engine.stop();
    } catch (_) {
      // A stopped or unavailable platform engine needs no recovery.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
  }
}

/// Selects a local English voice, preferring en-US.
///
/// Android marks network voices with `network_required=1`. Unknown voice
/// structures fail closed so speech cannot silently add a network dependency.
Map<String, String>? selectOfflineEnglishVoice(Object? rawVoices) {
  if (rawVoices is! List<Object?>) return null;
  Map<String, String>? fallback;
  for (final Object? rawVoice in rawVoices) {
    if (rawVoice is! Map<Object?, Object?>) continue;
    final String networkRequired =
        rawVoice['network_required']?.toString().toLowerCase() ?? '0';
    if (networkRequired == '1' || networkRequired == 'true') continue;
    final String locale = rawVoice['locale']?.toString() ?? '';
    if (!locale.toLowerCase().startsWith('en')) continue;
    final String name = rawVoice['name']?.toString() ?? '';
    final String identifier = rawVoice['identifier']?.toString() ?? '';
    if (name.isEmpty && identifier.isEmpty) continue;
    final Map<String, String> voice = <String, String>{
      'locale': locale,
      if (name.isNotEmpty) 'name': name,
      if (identifier.isNotEmpty) 'identifier': identifier,
    };
    if (locale.toLowerCase().startsWith('en-us')) return voice;
    fallback ??= voice;
  }
  return fallback;
}
