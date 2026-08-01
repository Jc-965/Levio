import 'package:wakelock_plus/wakelock_plus.dart';

int _holders = 0;

/// Refcounted wakelock: nested session screens (exercise video pushing the
/// motion coach) each acquire/release without a child's dispose turning the
/// screen timeout back on for its still-active parent.
Future<void> acquireSessionWakelock() async {
  _holders++;
  if (_holders == 1) {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Unavailable on this platform (tests).
    }
  }
}

Future<void> releaseSessionWakelock() async {
  if (_holders == 0) return;
  _holders--;
  if (_holders == 0) {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Unavailable on this platform (tests).
    }
  }
}
