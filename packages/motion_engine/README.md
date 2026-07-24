# Motion Engine

Pure Dart, camera-independent motion analysis for ParkiWell. The package
accepts the versioned `pose-stream.v1` and `exercise-template.v1` contracts and
returns `analysis-metrics.v1` data.

It currently supports the draft seated bilateral lateral arm raise and ports
the Python reference engine's:

- 3D joint-angle features;
- timestamp-aware gap interpolation and offline Butterworth filtering;
- tracking, sampling-rate, and pose-discontinuity abstention;
- finite-state repetition segmentation;
- bilateral validation and ROM, tempo, and symmetry metrics.

The package deliberately has no Flutter, camera, MediaPipe, network, or storage
dependency. ParkiWell's app adapter owns frame capture and translates its native
MediaPipe runtime into the shared pose contract.

This copy is synchronized with the motion-coach-cv reference implementation at
commit `7260b0e`. Keeping it in this repository makes ParkiWell builds
self-contained while preserving the independently verified Dart/Python parity
boundary.

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
