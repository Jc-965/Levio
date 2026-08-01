import 'package:flutter/material.dart';

import '../services/tutorial_service.dart';
import '../theme/app_theme.dart';
import 'tutorial_tooltip.dart';

class TutorialOverlay extends StatefulWidget {
  final Widget child;
  final List<TutorialStep> steps;
  final bool enabled;

  const TutorialOverlay({
    super.key,
    required this.child,
    required this.steps,
    this.enabled = true,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final TutorialService _service = TutorialService();
  final GlobalKey _overlayStackKey = GlobalKey();
  Rect? _targetRect;
  int _lastStepIndex = -1;
  int _lastEnsuredVisibleStepIndex = -1;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onTutorialChanged);
    _startIfNeeded();
  }

  @override
  void didUpdateWidget(covariant TutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.steps != widget.steps) {
      _startIfNeeded();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onTutorialChanged);
    super.dispose();
  }

  Future<void> _startIfNeeded() async {
    if (!widget.enabled) return;
    if (widget.steps.isEmpty) return;
    if (_service.isActive) return;

    final shouldShow = await _service.shouldShowTutorial();
    if (!mounted || !shouldShow) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _service.start(widget.steps);
      _refreshTargetRect();
    });
  }

  void _onTutorialChanged() {
    if (!mounted) return;
    if (_service.restartRequested &&
        !_service.isActive &&
        widget.enabled &&
        widget.steps.isNotEmpty) {
      _service.consumeRestartRequest();
      _startIfNeeded();
    }
    if (_service.currentStepIndex != _lastStepIndex) {
      _lastStepIndex = _service.currentStepIndex;
      _lastEnsuredVisibleStepIndex = -1;
      setState(() => _targetRect = null);
    }
    _refreshTargetRect();
  }

  void _refreshTargetRect() {
    final step = _service.currentStep;
    if (step == null) {
      _lastEnsuredVisibleStepIndex = -1;
      setState(() => _targetRect = null);
      return;
    }

    Future<void> tryFindRect({int attempt = 0}) async {
      if (!mounted) return;
      final current = _service.currentStep;
      if (current == null) return;
      final targetContext = current.targetKey.currentContext;
      if (targetContext == null) {
        _scheduleRetry(attempt, tryFindRect);
        return;
      }
      if (_lastEnsuredVisibleStepIndex != _service.currentStepIndex) {
        _lastEnsuredVisibleStepIndex = _service.currentStepIndex;
        try {
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: 0.32,
          );
          await Future<void>.delayed(const Duration(milliseconds: 70));
        } catch (_) {
          // Some targets are not inside a scrollable; ignore and continue.
        }
      }
      final rect = _findTargetRect(current);
      if (rect != null) {
        setState(() => _targetRect = rect);
        return;
      }
      _scheduleRetry(attempt, tryFindRect);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryFindRect());
  }

  void _scheduleRetry(
    int attempt,
    Future<void> Function({int attempt}) tryFindRect,
  ) {
    const delays = [120, 260, 420, 650, 950];
    if (attempt < delays.length) {
      Future.delayed(Duration(milliseconds: delays[attempt]), () {
        if (!mounted) return;
        tryFindRect(attempt: attempt + 1);
      });
      return;
    }
    setState(() => _targetRect = null);
  }

  Rect? _findTargetRect(TutorialStep step) {
    final targetContext = step.targetKey.currentContext;
    final overlayContext = _overlayStackKey.currentContext;
    if (targetContext == null || overlayContext == null) return null;
    if (!_isTargetInOverlaySubtree(targetContext, overlayContext)) {
      return null;
    }

    final renderBox = targetContext.findRenderObject() as RenderBox?;
    final overlayBox = overlayContext.findRenderObject() as RenderBox?;
    if (renderBox == null ||
        overlayBox == null ||
        !renderBox.hasSize ||
        !overlayBox.hasSize ||
        !renderBox.attached ||
        !overlayBox.attached) {
      return null;
    }

    final rectInOverlay = MatrixUtils.transformRect(
      renderBox.getTransformTo(overlayBox),
      renderBox.paintBounds,
    );
    final padding = step.spotlightPadding;

    return Rect.fromLTWH(
      rectInOverlay.left - padding.left,
      rectInOverlay.top - padding.top,
      rectInOverlay.width + padding.horizontal,
      rectInOverlay.height + padding.vertical,
    );
  }

  bool _isTargetInOverlaySubtree(
    BuildContext targetContext,
    BuildContext overlayContext,
  ) {
    final overlayElement = overlayContext as Element;
    var isDescendant = false;
    (targetContext as Element).visitAncestorElements((ancestor) {
      if (identical(ancestor, overlayElement)) {
        isDescendant = true;
        return false;
      }
      return true;
    });
    return isDescendant || identical(targetContext, overlayContext);
  }

  @override
  Widget build(BuildContext context) {
    final step = _service.currentStep;
    if (_service.isActive && step != null && _targetRect == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshTargetRect();
      });
    }
    return Stack(
      key: _overlayStackKey,
      children: [
        widget.child,
        if (_service.isActive && step != null)
          _buildOverlay(context, step, _targetRect),
      ],
    );
  }

  Widget _buildOverlay(
    BuildContext context,
    TutorialStep step,
    Rect? targetRect,
  ) {
    final colors = context.colors;
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    const tooltipWidth = 320.0;
    const tooltipHeight = 200.0;
    const horizontalInset = 20.0;
    const bubbleGap = 12.0;

    final hasTarget = targetRect != null;
    final rect = targetRect ?? const Rect.fromLTWH(0, 0, 1, 1);

    double left = rect.center.dx - (tooltipWidth / 2);
    left = left.clamp(
      horizontalInset,
      size.width - tooltipWidth - horizontalInset,
    );

    final showAbove = step.tooltipPosition == TutorialTooltipPosition.above;
    final topIfAbove = rect.top - tooltipHeight - bubbleGap;
    final topIfBelow = rect.bottom + bubbleGap;
    final minTop = padding.top + 10;
    final maxTop = size.height - padding.bottom - tooltipHeight - 10;

    double top;
    if (hasTarget) {
      if (showAbove) {
        if (topIfAbove >= minTop) {
          top = topIfAbove;
        } else {
          top = topIfBelow.clamp(minTop, maxTop);
        }
      } else {
        if (topIfBelow <= maxTop) {
          top = topIfBelow;
        } else {
          top = topIfAbove.clamp(minTop, maxTop);
        }
      }
    } else {
      top = (size.height - padding.bottom - tooltipHeight - 24).clamp(
        minTop,
        maxTop,
      );
    }

    final isLast = _service.currentStepIndex == _service.totalSteps - 1;

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // BlockSemantics hides the app behind the modal overlay from
            // screen readers; the barrier itself absorbs taps silently and
            // is excluded so readers land directly on the tooltip.
            Positioned.fill(
              child: BlockSemantics(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      targetRect: rect,
                      overlayColor: colors.textPrimary.withValues(alpha: 0.52),
                      showSpotlight: hasTarget,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: tooltipWidth,
              child: TutorialTooltip(
                title: step.title,
                description: step.description,
                actionLabel: step.actionLabel ?? (isLast ? 'Done' : 'Next'),
                currentStep: _service.currentStepIndex + 1,
                totalSteps: _service.totalSteps,
                onNext: () async => _service.next(),
                onSkip: () async => _service.skip(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final Color overlayColor;
  final bool showSpotlight;

  _SpotlightPainter({
    required this.targetRect,
    required this.overlayColor,
    this.showSpotlight = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showSpotlight &&
        targetRect.width > 1 &&
        targetRect.height > 1 &&
        targetRect.left < size.width &&
        targetRect.top < size.height &&
        targetRect.right > 0 &&
        targetRect.bottom > 0) {
      final overlayPath = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      final spotlight = RRect.fromRectAndRadius(
        targetRect,
        const Radius.circular(18),
      );
      final spotlightPath = Path()..addRRect(spotlight);
      final diffPath = Path.combine(
        PathOperation.difference,
        overlayPath,
        spotlightPath,
      );
      canvas.drawPath(diffPath, Paint()..color = overlayColor);
      canvas.drawRRect(
        spotlight,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = overlayColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.showSpotlight != showSpotlight;
  }
}
