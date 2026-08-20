# Motion Engine

Pure Dart, camera-independent motion analysis for ParkiWell. The package
accepts the versioned `pose-stream.v1` and `exercise-template.v1` contracts and
returns `analysis-metrics.v1` data.

It ports the Python reference engine's:

- 3D joint-angle features;
- timestamp-aware gap interpolation and offline Butterworth filtering;
- tracking, sampling-rate, and pose-discontinuity abstention;
- finite-state repetition segmentation;
- bilateral validation and ROM, tempo, and symmetry metrics (draft seated
  bilateral lateral arm raise);
- a declarative multi-exercise library (`exercise_specs.dart`) with a causal
  live coach that scores every repetition 0–100 across
  range/tempo/smoothness/symmetry with allowlisted cues
  (`live_exercise_coach.dart`);
- multi-step routine sessions that emit `session-evaluation.v1` documents
  (`routine_session.dart`).

The package deliberately has no Flutter, camera, MediaPipe, network, or storage
dependency. ParkiWell's app adapter owns frame capture and translates its native
MediaPipe runtime into the shared pose contract.

Cross-language parity (golden analysis fixtures and live/routine parity
replays) is enforced in the engine repository's own CI on every change; this
vendored copy carries only the fixture-free unit tests. Re-vendor with the
engine repo's sync procedure rather than editing files here.

This copy is synchronized with the motion-coach-cv reference implementation at
commit `20459a6`. Keeping it in this repository makes ParkiWell builds
self-contained while preserving the independently verified Dart/Python parity
boundary (live-engine and routine behavior are pinned there by cross-language
parity fixtures).

```dart
final result = analyzePoseStream(
  PoseStream.fromJson(poseStreamJson),
  ExerciseTemplate.fromJson(exerciseTemplateJson),
  engineVersion: '0.3.0',
);

// A convenience boundary is also available when both inputs are JSON maps.
final jsonResult = analyzePoseDocuments(
  poseStreamJson,
  exerciseTemplateJson,
  engineVersion: '0.3.0',
);
```

Run the package checks from this directory:

```bash
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib
dart analyze --fatal-infos
```
