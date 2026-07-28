import 'package:flutter/material.dart';

/// Directional fade-through transition between stages of a flow.
///
/// The outgoing stage fades out completely during the first third while
/// drifting toward the leading edge, then the incoming stage eases in from
/// the trailing edge — the two never overlap, so old content can't ghost
/// under the new. The host must paint a continuous backdrop behind this
/// switcher (both stages briefly reveal it mid-transition). Set [reverse]
/// before switching [child] when navigating back so the motion mirrors.
/// Stages are told apart by their keys, so each stage must carry a unique
/// key.
class StageTransitionSwitcher extends StatelessWidget {
  const StageTransitionSwitcher({
    super.key,
    required this.child,
    this.reverse = false,
    this.duration = const Duration(milliseconds: 400),
  });

  final Widget child;
  final bool reverse;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (stage, animation) {
        final incoming = stage.key == child.key;
        final direction = reverse ? -1.0 : 1.0;

        // Outgoing children play their animation in reverse (1 -> 0), so the
        // tween is written in entrance terms: exiting moves toward `begin`.
        final slide =
            Tween<Offset>(
              begin: Offset((incoming ? 0.04 : -0.04) * direction, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: incoming ? Curves.easeOutQuint : Curves.easeInOutSine,
              ),
            );
        // Fade-through: the outgoing stage (evaluated in reverse) clears
        // within the first ~30% while the incoming stage starts rising at
        // ~22%, so their tails overlap just enough that the screen never
        // reads as empty, yet old content can't linger under the new.
        final fade = CurvedAnimation(
          parent: animation,
          curve: incoming
              ? const Interval(0.22, 1, curve: Curves.easeOutCubic)
              : const Interval(0.7, 1, curve: Curves.easeInOutSine),
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: stage),
        );
      },
      child: child,
    );
  }
}
