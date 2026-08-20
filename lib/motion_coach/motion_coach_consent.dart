import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time consent for camera-based motion measurement.
///
/// Every entry point that opens the camera for pose analysis must pass this
/// gate: the motion-check flow, guided routines, and single-exercise practice
/// all process camera frames the same way, so consent given on any one of
/// them covers the others.
const String motionCoachConsentKey = 'motion_coach_mediapipe_consent_v1';

Future<bool> ensureMotionCoachConsent(BuildContext context) async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  if (preferences.getBool(motionCoachConsentKey) == true) return true;
  if (!context.mounted) return false;

  final bool? accepted = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Motion check privacy'),
      content: const Text(
        'Your camera images, recording, and pose landmarks are processed '
        'on this device. Google MediaPipe may receive performance and usage '
        'metrics about its on-device API, but not your images, video, or '
        'pose landmarks.\n\n'
        'Motion check offers general movement observations. It is not a '
        'diagnosis or medical assessment.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;
  await preferences.setBool(motionCoachConsentKey, true);
  return true;
}
