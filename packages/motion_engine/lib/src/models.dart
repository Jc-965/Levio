/// Camera-independent data contracts consumed by the motion engine.
library;

typedef AnalysisDocument = Map<String, Object?>;

final class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);

  Vector3 operator +(Vector3 other) =>
      Vector3(x + other.x, y + other.y, z + other.z);

  Vector3 operator /(double divisor) =>
      Vector3(x / divisor, y / divisor, z / divisor);
}

final class PoseLandmark {
  const PoseLandmark({
    required this.position,
    required this.visibility,
  });

  factory PoseLandmark.fromJson(Map<String, Object?> json) {
    final Object? x = json['x'];
    final Object? y = json['y'];
    final Object? z = json['z'];
    final Object? visibility = json['visibility'];
    return PoseLandmark(
      position: x is num && y is num && z is num
          ? Vector3(x.toDouble(), y.toDouble(), z.toDouble())
          : null,
      visibility: _number(visibility, 'landmark.visibility'),
    );
  }

  final Vector3? position;
  final double visibility;
}

final class PoseFrame {
  const PoseFrame({
    required this.timestampMs,
    required this.landmarks,
  });

  factory PoseFrame.fromJson(Map<String, Object?> json) {
    final int timestampMs = _integer(json['timestamp_ms'], 'timestamp_ms');
    final Object? serialized = json['landmarks'];
    if (serialized == null) {
      return PoseFrame(timestampMs: timestampMs, landmarks: null);
    }
    final List<Object?> values = _list(serialized, 'landmarks');
    if (values.length != 33) {
      throw const FormatException(
          'each detected pose must contain 33 landmarks');
    }
    return PoseFrame(
      timestampMs: timestampMs,
      landmarks: values
          .map((Object? value) => PoseLandmark.fromJson(
                _map(value, 'landmark'),
              ))
          .toList(growable: false),
    );
  }

  final int timestampMs;
  final List<PoseLandmark>? landmarks;
}

final class PoseModelContract {
  const PoseModelContract({
    required this.runtime,
    required this.model,
    required this.version,
    required this.coordinateSpace,
  });

  factory PoseModelContract.fromJson(Map<String, Object?> json) =>
      PoseModelContract(
        runtime: _string(json['runtime'], 'pose_model.runtime'),
        model: _string(json['model'], 'pose_model.model'),
        version: _string(json['version'], 'pose_model.version'),
        coordinateSpace:
            _string(json['coordinate_space'], 'pose_model.coordinate_space'),
      );

  final String runtime;
  final String model;
  final String version;
  final String coordinateSpace;
}

final class CameraContract {
  const CameraContract({
    required this.orientation,
    required this.mirrored,
    required this.width,
    required this.height,
  });

  factory CameraContract.fromJson(Map<String, Object?> json) => CameraContract(
        orientation: _string(json['orientation'], 'camera.orientation'),
        mirrored: _boolean(json['mirrored'], 'camera.mirrored'),
        width: _integer(json['width'], 'camera.width'),
        height: _integer(json['height'], 'camera.height'),
      );

  final String orientation;
  final bool mirrored;
  final int width;
  final int height;
}

final class PoseStream {
  PoseStream({
    required this.schemaVersion,
    required this.engineVersion,
    required this.poseModel,
    required this.camera,
    required this.frames,
  }) {
    if (schemaVersion != 'pose-stream.v1') {
      throw const FormatException('unsupported pose stream schema');
    }
    for (int index = 1; index < frames.length; index += 1) {
      if (frames[index].timestampMs <= frames[index - 1].timestampMs) {
        throw const FormatException(
            'frame timestamps must be strictly increasing');
      }
    }
  }

  factory PoseStream.fromJson(Map<String, Object?> json) => PoseStream(
        schemaVersion: _string(json['schema_version'], 'schema_version'),
        engineVersion: _string(json['engine_version'], 'engine_version'),
        poseModel:
            PoseModelContract.fromJson(_map(json['pose_model'], 'pose_model')),
        camera: CameraContract.fromJson(_map(json['camera'], 'camera')),
        frames: _list(json['frames'], 'frames')
            .map((Object? value) => PoseFrame.fromJson(_map(value, 'frame')))
            .toList(growable: false),
      );

  final String schemaVersion;
  final String engineVersion;
  final PoseModelContract poseModel;
  final CameraContract camera;
  final List<PoseFrame> frames;
}

final class ConfidencePolicy {
  const ConfidencePolicy({
    required this.visibilityThreshold,
    required this.minimumSessionCoverage,
    required this.minimumSamplingHz,
    required this.maximumInterpolatedGapFrames,
  });

  factory ConfidencePolicy.fromJson(Map<String, Object?> json) =>
      ConfidencePolicy(
        visibilityThreshold:
            _number(json['visibility_threshold'], 'visibility_threshold'),
        minimumSessionCoverage: _number(
          json['minimum_session_coverage'],
          'minimum_session_coverage',
        ),
        minimumSamplingHz:
            _number(json['minimum_sampling_hz'], 'minimum_sampling_hz'),
        maximumInterpolatedGapFrames: _integer(
          json['maximum_interpolated_gap_frames'],
          'maximum_interpolated_gap_frames',
        ),
      );

  final double visibilityThreshold;
  final double minimumSessionCoverage;
  final double minimumSamplingHz;
  final int maximumInterpolatedGapFrames;
}

final class ExerciseTemplate {
  ExerciseTemplate({
    required this.schemaVersion,
    required this.templateVersion,
    required this.exerciseId,
    required this.poseContract,
    required this.allowedOrientations,
    required this.primarySignal,
    required this.requiredLandmarks,
    required this.referenceRomDeg,
    required this.referenceTempoS,
    required this.confidencePolicy,
  }) {
    if (schemaVersion != 'exercise-template.v1') {
      throw const FormatException('unsupported exercise template schema');
    }
    if (templateVersion < 1) {
      throw const FormatException('template version must be positive');
    }
  }

  factory ExerciseTemplate.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> rep = _map(json['rep'], 'rep');
    final String primarySignal =
        _string(json['primary_signal'], 'primary_signal');
    final Map<String, Object?> rom = _map(rep['rom_deg'], 'rep.rom_deg');
    final Map<String, Object?> primaryRom =
        _map(rom[primarySignal], 'primary ROM');
    final Map<String, Object?> tempo = _map(rep['tempo_s'], 'rep.tempo_s');
    final Map<String, Object?> camera =
        _map(json['camera_contract'], 'camera_contract');
    return ExerciseTemplate(
      schemaVersion: _string(json['schema_version'], 'schema_version'),
      templateVersion: _integer(json['template_version'], 'template_version'),
      exerciseId: _string(json['exercise_id'], 'exercise_id'),
      poseContract: PoseModelContract.fromJson(
          _map(json['pose_contract'], 'pose_contract')),
      allowedOrientations: _list(
        camera['allowed_orientations'],
        'allowed_orientations',
      ).map((Object? value) => _string(value, 'orientation')).toSet(),
      primarySignal: primarySignal,
      requiredLandmarks: _list(
        json['required_landmarks'],
        'required_landmarks',
      ).map((Object? value) => _string(value, 'required landmark')).toList(),
      referenceRomDeg: _number(primaryRom['median'], 'ROM median'),
      referenceTempoS: _number(tempo['median'], 'tempo median'),
      confidencePolicy: ConfidencePolicy.fromJson(
        _map(json['confidence_policy'], 'confidence_policy'),
      ),
    );
  }

  final String schemaVersion;
  final int templateVersion;
  final String exerciseId;
  final PoseModelContract poseContract;
  final Set<String> allowedOrientations;
  final String primarySignal;
  final List<String> requiredLandmarks;
  final double referenceRomDeg;
  final double referenceTempoS;
  final ConfidencePolicy confidencePolicy;
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String name) {
  if (value is! List<Object?>) {
    throw FormatException('$name must be a list');
  }
  return value;
}

String _string(Object? value, String name) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$name must be a non-empty string');
  }
  return value;
}

double _number(Object? value, String name) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$name must be a finite number');
  }
  return value.toDouble();
}

int _integer(Object? value, String name) {
  if (value is! int) {
    throw FormatException('$name must be an integer');
  }
  return value;
}

bool _boolean(Object? value, String name) {
  if (value is! bool) {
    throw FormatException('$name must be a boolean');
  }
  return value;
}
