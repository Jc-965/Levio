import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion_pose_bridge.dart';

/// One detected pose in normalized image coordinates, ready to paint.
///
/// Flat `[x, y, visibility]` triplets for the 33 landmarks. Kept minimal on
/// purpose: this is produced at camera rate, so it must stay cheap to build
/// and must never retain the platform detection object.
class MotionSkeletonFrame {
  MotionSkeletonFrame._(this._values);

  /// Returns null unless the detection holds exactly one complete pose.
  static MotionSkeletonFrame? fromDetection(MotionPoseDetection detection) {
    final List<MotionPoseLandmark>? landmarks = detection.normalizedLandmarks;
    if (detection.poseCount != 1 ||
        landmarks == null ||
        landmarks.length != 33) {
      return null;
    }
    final Float32List values = Float32List(99);
    for (int index = 0; index < 33; index += 1) {
      final MotionPoseLandmark landmark = landmarks[index];
      values[index * 3] = landmark.x;
      values[index * 3 + 1] = landmark.y;
      values[index * 3 + 2] = landmark.visibility < landmark.presence
          ? landmark.visibility
          : landmark.presence;
    }
    return MotionSkeletonFrame._(values);
  }

  final Float32List _values;

  double x(int landmark) => _values[landmark * 3];
  double y(int landmark) => _values[landmark * 3 + 1];
  double visibility(int landmark) => _values[landmark * 3 + 2];
}

/// Landmark pairs drawn as bones; the same readable subset the
/// demonstration figure uses, plus forearm/hand emphasis is unnecessary.
const List<List<int>> _skeletonBones = <List<int>>[
  <int>[11, 12],
  <int>[23, 24],
  <int>[11, 23],
  <int>[12, 24],
  <int>[11, 13],
  <int>[13, 15],
  <int>[12, 14],
  <int>[14, 16],
  <int>[23, 25],
  <int>[25, 27],
  <int>[24, 26],
  <int>[26, 28],
];

/// Every landmark that appears in [_skeletonBones]; joints are drawn from
/// this set so end-of-chain landmarks (wrists, ankles) get markers too.
const List<int> _skeletonJoints = <int>[
  11,
  12,
  13,
  14,
  15,
  16,
  23,
  24,
  25,
  26,
  27,
  28,
];

const double _minimumVisibility = 0.5;

/// Live tracking overlay for the camera preview.
///
/// Listens to a [ValueListenable] rather than the session controller so that
/// per-frame pose updates repaint only this small canvas, never the
/// surrounding screen; the controller's coarse notifications stay gated on
/// meaningful changes.
class MotionSkeletonOverlay extends StatelessWidget {
  const MotionSkeletonOverlay({
    super.key,
    required this.frame,
    required this.mirrored,
    this.color = Colors.white,
  });

  final ValueListenable<MotionSkeletonFrame?> frame;

  /// True when the preview under this overlay is horizontally mirrored, as
  /// front-camera previews are; landmark x coordinates are flipped to match.
  final bool mirrored;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<MotionSkeletonFrame?>(
        valueListenable: frame,
        builder: (BuildContext context, MotionSkeletonFrame? value, _) {
          return CustomPaint(
            painter: _SkeletonPainter(
              frame: value,
              mirrored: mirrored,
              color: color,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

final Paint _bonePaint = Paint()
  ..strokeWidth = 3
  ..strokeCap = StrokeCap.round
  ..style = PaintingStyle.stroke;
final Paint _jointPaint = Paint();

class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({
    required this.frame,
    required this.mirrored,
    required this.color,
  });

  final MotionSkeletonFrame? frame;
  final bool mirrored;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final MotionSkeletonFrame? pose = frame;
    if (pose == null) return;
    _bonePaint.color = color.withValues(alpha: 0.85);
    _jointPaint.color = color;

    Offset? project(int landmark) {
      if (pose.visibility(landmark) < _minimumVisibility) return null;
      final double x = mirrored ? 1 - pose.x(landmark) : pose.x(landmark);
      return Offset(x * size.width, pose.y(landmark) * size.height);
    }

    for (final List<int> pair in _skeletonBones) {
      final Offset? first = project(pair[0]);
      final Offset? second = project(pair[1]);
      if (first == null || second == null) continue;
      canvas.drawLine(first, second, _bonePaint);
    }
    for (final int landmark in _skeletonJoints) {
      final Offset? point = project(landmark);
      if (point != null) canvas.drawCircle(point, 3.5, _jointPaint);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.mirrored != mirrored ||
      oldDelegate.color != color;
}
