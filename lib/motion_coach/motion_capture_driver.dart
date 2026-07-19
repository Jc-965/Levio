import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion_coach_session.dart';
import 'motion_pose_bridge.dart';

typedef MotionSampleCallback = void Function(MotionPoseSample sample);

abstract interface class MotionCaptureDriver {
  bool get isInitialized;
  bool get isRecording;
  double get aspectRatio;

  Future<void> initialize(MotionSampleCallback onSample);
  Widget buildPreview();
  Future<void> startRecording();
  Future<String> stopRecording();
  Future<void> cancelRecording();
  Future<void> dispose();
}

class CameraMotionCaptureDriver implements MotionCaptureDriver {
  CameraMotionCaptureDriver({MotionPoseBridge? poseBridge})
    : _poseBridge = poseBridge ?? MotionPoseBridge();

  final MotionPoseBridge _poseBridge;
  final Stopwatch _clock = Stopwatch();
  CameraController? _camera;
  CameraDescription? _description;
  MotionSampleCallback? _onSample;
  bool _processingFrame = false;
  bool _disposed = false;

  @override
  bool get isInitialized => _camera?.value.isInitialized == true;

  @override
  bool get isRecording => _camera?.value.isRecordingVideo == true;

  @override
  double get aspectRatio => _camera?.value.aspectRatio ?? 3 / 4;

  @override
  Future<void> initialize(MotionSampleCallback onSample) async {
    if (_disposed) {
      throw StateError('A disposed camera driver cannot be reused');
    }
    _onSample = onSample;
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException(
        'NoCamera',
        'No camera is available on this device.',
      );
    }
    _description = cameras.firstWhere(
      (CameraDescription camera) =>
          camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final CameraController controller = CameraController(
      _description!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    _camera = controller;
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await _poseBridge.initialize();
    _clock
      ..reset()
      ..start();
    await controller.startImageStream(_handleImage);
  }

  @override
  Widget buildPreview() {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(camera);
  }

  @override
  Future<void> startRecording() async {
    final CameraController camera = _requireCamera();
    if (camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
    await camera.startVideoRecording(
      onAvailable: _handleImage,
      enablePersistentRecording: false,
    );
  }

  @override
  Future<String> stopRecording() async {
    final CameraController camera = _requireCamera();
    final XFile file = await camera.stopVideoRecording();
    return file.path;
  }

  @override
  Future<void> cancelRecording() async {
    final CameraController? camera = _camera;
    if (camera?.value.isRecordingVideo != true) return;
    final XFile file = await camera!.stopVideoRecording();
    final File recording = File(file.path);
    if (await recording.exists()) {
      await recording.delete();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _clock.stop();
    final CameraController? camera = _camera;
    _camera = null;
    _onSample = null;
    try {
      if (camera?.value.isRecordingVideo == true) {
        final XFile file = await camera!.stopVideoRecording();
        final File recording = File(file.path);
        if (await recording.exists()) {
          await recording.delete();
        }
      } else if (camera?.value.isStreamingImages == true) {
        await camera!.stopImageStream();
      }
    } catch (_) {
      // The platform may already have released the camera during lifecycle exit.
    }
    await camera?.dispose();
    await _poseBridge.dispose();
  }

  CameraController _requireCamera() {
    final CameraController? camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      throw StateError('Camera is not initialized');
    }
    return camera;
  }

  Future<void> _handleImage(CameraImage image) async {
    if (_processingFrame || _disposed || _onSample == null) return;
    _processingFrame = true;
    final int timestampMs = _clock.elapsedMilliseconds;
    try {
      final CameraDescription description = _description!;
      final MotionPoseDetection detection = await _poseBridge.detect(
        image: image,
        sensorOrientation: description.sensorOrientation,
        isFrontCamera: description.lensDirection == CameraLensDirection.front,
        timestampMs: timestampMs,
      );
      if (!_disposed) {
        final bool swapsDimensions =
            description.sensorOrientation.abs() % 180 == 90;
        _onSample?.call(
          MotionPoseSample(
            detection: detection,
            frameWidth: swapsDimensions ? image.height : image.width,
            frameHeight: swapsDimensions ? image.width : image.height,
          ),
        );
      }
    } on Object {
      if (!_disposed) {
        final int orientation = _description?.sensorOrientation ?? 0;
        final bool swapsDimensions = orientation.abs() % 180 == 90;
        _onSample?.call(
          MotionPoseSample(
            detection: MotionPoseDetection.empty(timestampMs: timestampMs),
            frameWidth: swapsDimensions ? image.height : image.width,
            frameHeight: swapsDimensions ? image.width : image.height,
          ),
        );
      }
    } finally {
      _processingFrame = false;
    }
  }
}
