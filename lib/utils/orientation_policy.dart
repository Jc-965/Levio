import 'package:flutter/services.dart';

/// The app-wide orientation policy set once at startup.
///
/// Any screen that narrows the allowed orientations (the motion coach locks
/// to portrait-up during capture) must restore THIS list on dispose, not an
/// empty one: an empty list defers to the OS default and silently discards
/// the app's portrait-only baseline for the rest of the process.
const List<DeviceOrientation> appPreferredOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];
