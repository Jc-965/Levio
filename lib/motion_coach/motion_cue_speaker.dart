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

  @override
  Future<void> initialize() => _initialization ??= _configure();

  Future<void> _configure() async {
    try {
      await _engine.setLanguage('en-US');
      await _engine.setSpeechRate(0.45);
      await _engine.setVolume(1);
      await _engine.setPitch(1);
      await _engine.awaitSpeakCompletion(false);
    } catch (_) {
      // Initialization is best effort; visual and haptic cues remain active.
    }
  }

  @override
  Future<void> speak(String text) async {
    if (_disposed || text.trim().isEmpty) return;
    try {
      await initialize();
      if (_disposed) return;
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
