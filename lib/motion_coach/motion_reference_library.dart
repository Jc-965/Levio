import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:motion_engine/motion_engine.dart';

import 'motion_exercise_catalog.dart';

/// Asset-backed source of the engine's reference documents.
///
/// `packages/motion_engine` deliberately has no Flutter, file, or network
/// dependency, so it consumes `exercise-template.v1` and `routine.v1`
/// documents that somebody else loads. This class is that adapter: it reads
/// the vendored assets once, caches them, and then hands the engine a purely
/// synchronous lookup, which is what [RoutineSession] requires.
///
/// Templates and routines are generated artifacts of the motion-coach-cv
/// engine repo; regenerate them with `scripts/sync-motion-assets.py` rather
/// than editing the JSON by hand.
class MotionReferenceLibrary {
  MotionReferenceLibrary({AssetBundle? bundle}) : _bundle = bundle;

  /// Process-wide instance so a template is decoded at most once per launch.
  /// Tests construct their own instances, reading the real bundled assets.
  static final MotionReferenceLibrary shared = MotionReferenceLibrary();

  static const String templateAssetPrefix = 'assets/motion/templates/';
  static const String routineAssetPrefix = 'assets/motion/routines/';
  static const String demonstrationAssetPrefix =
      'assets/motion/demonstrations/';

  final AssetBundle? _bundle;
  final Map<String, Map<String, Object?>> _templates =
      <String, Map<String, Object?>>{};
  final Map<String, MotionDemonstrationLoop> _demonstrations =
      <String, MotionDemonstrationLoop>{};
  final Map<String, RoutineDefinition> _routines =
      <String, RoutineDefinition>{};

  AssetBundle get _assets => _bundle ?? rootBundle;

  bool get isLoaded => _templates.isNotEmpty;

  /// Load every template referenced by the catalog. Routines and
  /// demonstrations stay lazy because a session only ever needs one.
  Future<void> loadTemplates() async {
    if (_templates.length == motionExerciseCatalog.length) return;
    for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
      await templateFor(exercise.exerciseId);
    }
  }

  Future<Map<String, Object?>> templateFor(String exerciseId) async {
    final Map<String, Object?>? cached = _templates[exerciseId];
    if (cached != null) return cached;
    final Map<String, Object?> document = await _decode(
      '$templateAssetPrefix$exerciseId.template.v1.json',
    );
    if (document['schema_version'] != 'exercise-template.v1') {
      throw FormatException('unsupported template schema for $exerciseId');
    }
    if (document['exercise_id'] != exerciseId) {
      throw FormatException('template $exerciseId declares a different id');
    }
    _templates[exerciseId] = document;
    return document;
  }

  /// Synchronous accessor for already-loaded templates.
  ///
  /// [RoutineSession] builds every step's coach in its constructor and cannot
  /// await, so callers must [loadTemplates] (or [loadRoutine]) first.
  Map<String, Object?> template(String exerciseId) {
    final Map<String, Object?>? document = _templates[exerciseId];
    if (document == null) {
      throw StateError('template $exerciseId was not loaded');
    }
    return document;
  }

  /// Load a routine and every template its steps reference.
  Future<RoutineDefinition> loadRoutine(String routineId) async {
    final RoutineDefinition? cached = _routines[routineId];
    if (cached != null) return cached;
    final Map<String, Object?> document = await _decode(
      '$routineAssetPrefix$routineId.json',
    );
    // Parsing validates the schema and that every exercise is registered in
    // the engine, so an unknown step fails here rather than mid-session.
    final RoutineDefinition routine = RoutineDefinition.fromJson(document);
    for (final RoutineStepDefinition step in routine.steps) {
      await templateFor(step.exerciseId);
    }
    _routines[routineId] = routine;
    return routine;
  }

  Future<MotionDemonstrationLoop> loadDemonstration(String exerciseId) async {
    final MotionDemonstrationLoop? cached = _demonstrations[exerciseId];
    if (cached != null) return cached;
    final String raw = await _assets.loadString(
      '$demonstrationAssetPrefix$exerciseId.demonstration-loop.v1.json',
    );
    // Demonstration loops are the largest motion assets (roughly 70-140 KB
    // of JSON); decoding them on the UI thread would land exactly when a
    // session screen is opening. Templates stay on-thread; they are tiny.
    final MotionDemonstrationLoop loop = await compute(
      _decodeDemonstrationLoop,
      raw,
    );
    _demonstrations[exerciseId] = loop;
    return loop;
  }

  /// Reference range and tempo the live engine will actually use, derived
  /// from the same template the analysis reads. Exposed so the UI never
  /// invents its own copy of a threshold.
  LiveExerciseCoachConfig configFor(String exerciseId) =>
      LiveExerciseCoachConfig.fromTemplateJson(template(exerciseId));

  Future<Map<String, Object?>> _decode(String assetKey) async {
    final String raw = await _assets.loadString(assetKey);
    final Object? document = jsonDecode(raw);
    if (document is! Map<String, Object?>) {
      throw FormatException('$assetKey is not a JSON object');
    }
    return document;
  }
}

/// Isolate entry point for [MotionReferenceLibrary.loadDemonstration].
MotionDemonstrationLoop _decodeDemonstrationLoop(String raw) {
  final Object? document = jsonDecode(raw);
  if (document is! Map<String, Object?>) {
    throw const FormatException('demonstration loop is not a JSON object');
  }
  return MotionDemonstrationLoop.fromJson(document);
}

/// Front-view stick-figure demonstration, decoded from the flat asset form.
///
/// Only x/y are stored: the guide is drawn as a 2D silhouette, so depth and
/// per-landmark visibility (always 1.0 for the analytic reference body) would
/// be dead weight in the bundle.
class MotionDemonstrationLoop {
  const MotionDemonstrationLoop({
    required this.exerciseId,
    required this.frameCount,
    required this.frameIntervalMs,
    required this.pointsXy,
  });

  factory MotionDemonstrationLoop.fromJson(Map<String, Object?> document) {
    if (document['schema_version'] != 'demonstration-loop.v1') {
      throw const FormatException('unsupported demonstration schema');
    }
    final int frameCount = (document['frame_count']! as num).toInt();
    final int landmarkCount = (document['landmark_count']! as num).toInt();
    final List<double> points = (document['points_xy']! as List<Object?>)
        .map((Object? value) => (value! as num).toDouble())
        .toList(growable: false);
    if (landmarkCount != 33 || points.length != frameCount * 33 * 2) {
      throw const FormatException('demonstration loop has inconsistent size');
    }
    return MotionDemonstrationLoop(
      exerciseId: document['exercise_id']! as String,
      frameCount: frameCount,
      frameIntervalMs: (document['frame_interval_ms']! as num).toInt(),
      pointsXy: points,
    );
  }

  final String exerciseId;
  final int frameCount;
  final int frameIntervalMs;
  final List<double> pointsXy;

  Duration get duration => Duration(milliseconds: frameIntervalMs * frameCount);

  /// The 33 landmark positions for [frameIndex], wrapped into the loop.
  List<Offset> frame(int frameIndex) {
    final int index = frameIndex % frameCount;
    final int base = index * 66;
    return List<Offset>.generate(
      33,
      (int landmark) => Offset(
        pointsXy[base + landmark * 2],
        pointsXy[base + landmark * 2 + 1],
      ),
      growable: false,
    );
  }

  int frameIndexAt(Duration elapsed) =>
      (elapsed.inMilliseconds ~/ frameIntervalMs) % frameCount;
}
