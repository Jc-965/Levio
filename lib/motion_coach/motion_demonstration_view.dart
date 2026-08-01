import 'package:flutter/material.dart';

import 'motion_reference_library.dart';

/// Landmark index pairs drawn as bones, in MediaPipe's 33-point topology.
///
/// A readable subset rather than the full connection list: fingers and the
/// facial mesh add clutter at phone size without telling the person anything
/// about the movement they are copying.
const List<List<int>> _demonstrationBones = <List<int>>[
  <int>[11, 12], // shoulders
  <int>[23, 24], // hips
  <int>[11, 23], // left torso
  <int>[12, 24], // right torso
  <int>[11, 13], <int>[13, 15], // left arm
  <int>[12, 14], <int>[14, 16], // right arm
  <int>[23, 25], <int>[25, 27], // left leg
  <int>[24, 26], <int>[26, 28], // right leg
  <int>[27, 31], <int>[28, 32], // feet
];

const int _noseLandmark = 0;
const List<int> _jointLandmarks = <int>[
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

/// Looping stick-figure demonstration of an exercise.
///
/// The engine ships a deterministic reference motion for every exercise, so
/// the app can show what to do without depending on a licensed video for
/// each one. This is a guide only — it is never compared against and never
/// scored.
class MotionDemonstrationView extends StatefulWidget {
  const MotionDemonstrationView({
    super.key,
    required this.loop,
    this.color,
    this.playing = true,
  });

  final MotionDemonstrationLoop loop;
  final Color? color;
  final bool playing;

  @override
  State<MotionDemonstrationView> createState() =>
      _MotionDemonstrationViewState();
}

class _MotionDemonstrationViewState extends State<MotionDemonstrationView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.loop.duration,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With reduce-motion on, hold a single reference pose instead of
    // looping; the written instructions carry the movement description.
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncPlayback();
  }

  void _syncPlayback() {
    final bool shouldPlay = widget.playing && !_reduceMotion;
    if (shouldPlay && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldPlay && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(MotionDemonstrationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A routine swaps in a different exercise's loop mid-flight; without
    // this, the controller would keep the first loop's duration and every
    // later demonstration would play at the wrong speed.
    if (widget.loop.exerciseId != oldWidget.loop.exerciseId ||
        widget.loop.duration != oldWidget.loop.duration) {
      _controller
        ..stop()
        ..duration = widget.loop.duration
        ..value = 0;
    }
    _syncPlayback();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Reused across animation ticks: paint() runs up to 60 times a second for
  // the whole session, so per-frame Paint construction is avoidable churn
  // alongside the live camera pipeline.
  final Paint _bonePaint = Paint()
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final Paint _jointPaint = Paint();
  final Paint _headPaint = Paint();
  Color? _paintedColor;

  void _syncPaints(Color color) {
    if (_paintedColor == color) return;
    _paintedColor = color;
    _bonePaint.color = color;
    _jointPaint.color = color.withValues(alpha: 0.85);
    _headPaint.color = color;
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? Theme.of(context).colorScheme.primary;
    _syncPaints(color);
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final int frameIndex = (_controller.value * widget.loop.frameCount)
            .floor();
        return CustomPaint(
          painter: _DemonstrationPainter(
            loop: widget.loop,
            frameIndex: frameIndex,
            bounds: _boundsOf(widget.loop),
            bonePaint: _bonePaint,
            jointPaint: _jointPaint,
            headPaint: _headPaint,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

final Map<String, Rect> _boundsCache = <String, Rect>{};

/// Bounds across the whole loop, so the figure never rescales mid-motion.
Rect _boundsOf(MotionDemonstrationLoop loop) {
  final Rect? cached = _boundsCache[loop.exerciseId];
  if (cached != null) return cached;
  double minX = double.infinity;
  double maxX = double.negativeInfinity;
  double minY = double.infinity;
  double maxY = double.negativeInfinity;
  for (int index = 0; index < loop.pointsXy.length; index += 2) {
    final double x = loop.pointsXy[index];
    final double y = loop.pointsXy[index + 1];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  final Rect bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  _boundsCache[loop.exerciseId] = bounds;
  return bounds;
}

class _DemonstrationPainter extends CustomPainter {
  const _DemonstrationPainter({
    required this.loop,
    required this.frameIndex,
    required this.bounds,
    required this.bonePaint,
    required this.jointPaint,
    required this.headPaint,
  });

  final MotionDemonstrationLoop loop;
  final int frameIndex;
  final Rect bounds;
  final Paint bonePaint;
  final Paint jointPaint;
  final Paint headPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.width <= 0 || bounds.height <= 0) return;
    const double margin = 12;
    final double scale = ((size.width - margin * 2) / bounds.width).clamp(
      0.0,
      (size.height - margin * 2) / bounds.height,
    );
    final Offset origin = Offset(
      size.width / 2 - bounds.center.dx * scale,
      size.height / 2 - bounds.center.dy * scale,
    );

    // Landmarks are read straight from the loop's flat coordinate array so
    // no per-tick list of Offsets is materialised.
    final List<double> points = loop.pointsXy;
    final int base = (frameIndex % loop.frameCount) * 66;
    Offset project(int landmark) => Offset(
      origin.dx + points[base + landmark * 2] * scale,
      origin.dy + points[base + landmark * 2 + 1] * scale,
    );

    for (final List<int> pair in _demonstrationBones) {
      canvas.drawLine(project(pair[0]), project(pair[1]), bonePaint);
    }
    for (final int landmark in _jointLandmarks) {
      canvas.drawCircle(project(landmark), 4.5, jointPaint);
    }

    // The head is drawn from the nose alone; the face mesh carries no
    // information about the exercise.
    final Offset shoulderCentre =
        Offset.lerp(project(11), project(12), 0.5) ?? project(_noseLandmark);
    final Offset nose = project(_noseLandmark);
    canvas.drawLine(shoulderCentre, nose, bonePaint);
    canvas.drawCircle(nose, scale * 0.09, headPaint);
  }

  @override
  bool shouldRepaint(_DemonstrationPainter oldDelegate) =>
      oldDelegate.frameIndex != frameIndex ||
      oldDelegate.loop != loop ||
      oldDelegate.bonePaint.color != bonePaint.color;
}
