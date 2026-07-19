import 'dart:io';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String motionPoseModelName = 'pose_landmarker_lite';
const String motionPoseModelVersion =
    'sha256:59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a';
const String _modelAsset =
    'packages/flutter_mediapipe_vision_platform_interface/'
    'assets/models/pose_landmarker_lite.task';
const String _modelSha256 =
    '59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a';

class MotionPoseBridge {
  MotionPoseBridge({
    MethodChannel channel = const MethodChannel(
      'com.parkiwell.app/motion_pose',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final String modelPath = await _ensureModelFile();
    await _channel.invokeMethod<void>('initialize', <String, Object?>{
      'modelPath': modelPath,
    });
    _initialized = true;
  }

  Future<MotionPoseDetection> detect({
    required CameraImage image,
    required int sensorOrientation,
    required bool isFrontCamera,
    required int timestampMs,
  }) async {
    if (!_initialized) {
      throw StateError('MotionPoseBridge must be initialized before detect');
    }

    final Map<Object?, Object?>? raw = await _channel
        .invokeMethod<Map<Object?, Object?>>('detect', <String, Object?>{
          'planes': image.planes
              .map((Plane plane) => plane.bytes)
              .toList(growable: false),
          'rowStrides': image.planes
              .map((Plane plane) => plane.bytesPerRow)
              .toList(growable: false),
          'pixelStrides': image.planes
              .map((Plane plane) => plane.bytesPerPixel ?? 1)
              .toList(growable: false),
          'width': image.width,
          'height': image.height,
          'format': image.format.group.name,
          'rotationDegrees': sensorOrientation,
          'isFrontCamera': isFrontCamera,
          'timestampMs': timestampMs,
        });

    if (raw == null) {
      return MotionPoseDetection.empty(timestampMs: timestampMs);
    }
    return MotionPoseDetection.fromMap(raw);
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    await _channel.invokeMethod<void>('dispose');
  }

  Future<String> _ensureModelFile() async {
    final Directory directory = await getApplicationSupportDirectory();
    final File file = File('${directory.path}/$motionPoseModelName.task');
    if (await file.exists()) {
      final Uint8List existing = await file.readAsBytes();
      if (sha256.convert(existing).toString() == _modelSha256) {
        return file.path;
      }
    }

    final ByteData asset = await rootBundle.load(_modelAsset);
    final Uint8List bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    final String digest = sha256.convert(bytes).toString();
    if (digest != _modelSha256) {
      throw StateError('Bundled pose model failed its integrity check');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

class MotionPoseDetection {
  const MotionPoseDetection({
    required this.timestampMs,
    required this.normalizedLandmarks,
    required this.worldLandmarks,
    required this.inferenceMs,
    this.poseCount = 1,
  });

  factory MotionPoseDetection.empty({required int timestampMs}) =>
      MotionPoseDetection(
        timestampMs: timestampMs,
        normalizedLandmarks: null,
        worldLandmarks: null,
        inferenceMs: 0,
        poseCount: 0,
      );

  factory MotionPoseDetection.fromMap(Map<Object?, Object?> raw) {
    final int timestampMs = (raw['timestampMs']! as num).toInt();
    return MotionPoseDetection(
      timestampMs: timestampMs,
      normalizedLandmarks: _landmarks(raw['landmarks']),
      worldLandmarks: _landmarks(raw['worldLandmarks']),
      inferenceMs: (raw['inferenceMs'] as num?)?.toDouble() ?? 0,
      poseCount: (raw['poseCount'] as num?)?.toInt() ?? 0,
    );
  }

  final int timestampMs;
  final List<MotionPoseLandmark>? normalizedLandmarks;
  final List<MotionPoseLandmark>? worldLandmarks;
  final double inferenceMs;
  final int poseCount;

  bool get hasCompletePose =>
      normalizedLandmarks?.length == 33 && worldLandmarks?.length == 33;

  static List<MotionPoseLandmark>? _landmarks(Object? value) {
    if (value is! List<Object?> || value.length != 33) return null;
    return value
        .map(
          (Object? entry) => MotionPoseLandmark.fromMap(
            Map<Object?, Object?>.from(entry! as Map<Object?, Object?>),
          ),
        )
        .toList(growable: false);
  }
}

class MotionPoseLandmark {
  const MotionPoseLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
    required this.presence,
  });

  factory MotionPoseLandmark.fromMap(Map<Object?, Object?> raw) =>
      MotionPoseLandmark(
        x: (raw['x']! as num).toDouble(),
        y: (raw['y']! as num).toDouble(),
        z: (raw['z']! as num).toDouble(),
        visibility: (raw['visibility'] as num?)?.toDouble() ?? 0,
        presence: (raw['presence'] as num?)?.toDouble() ?? 0,
      );

  final double x;
  final double y;
  final double z;
  final double visibility;
  final double presence;
}
