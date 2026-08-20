import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/app_logger.dart';

/// A bundled public-domain demonstration clip, looping and muted.
///
/// Used only outside live capture (intro sheets): decoding video while the
/// camera and pose model are running would compete for the same frame
/// budget. Honors the system reduce-motion setting by holding the first
/// frame instead of playing. On any load failure the caller's fallback
/// (the animated guide) is shown via [onUnavailable].
class MotionDemoVideoView extends StatefulWidget {
  const MotionDemoVideoView({
    super.key,
    required this.assetPath,
    this.onUnavailable,
  });

  final String assetPath;
  final VoidCallback? onUnavailable;

  @override
  State<MotionDemoVideoView> createState() => _MotionDemoVideoViewState();
}

class _MotionDemoVideoViewState extends State<MotionDemoVideoView> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final VideoPlayerController controller = VideoPlayerController.asset(
      widget.assetPath,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) return;
      // With reduce-motion on, hold the first frame; a tap still starts
      // playback deliberately, so the demonstration is never unreachable.
      final bool reduceMotion = MediaQuery.of(context).disableAnimations;
      if (!reduceMotion) {
        await controller.play();
      }
      if (mounted) setState(() {});
    } on Object catch (error, stackTrace) {
      AppLogger().warning(
        'Demo video ${widget.assetPath} failed to load',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onUnavailable?.call();
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    if (_failed) {
      // The caller normally swaps in the animated guide via [onUnavailable];
      // this icon is the last-resort rendering, never a stuck spinner.
      return Center(
        child: Icon(
          Icons.accessibility_new_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool playing = controller.value.isPlaying;
    return Semantics(
      button: true,
      label: playing
          ? 'Demonstration video playing. Double tap to pause.'
          : 'Demonstration video paused. Double tap to play.',
      child: GestureDetector(
        onTap: () async {
          // Read the live state, not the build-time capture: two quick
          // taps must toggle twice, not repeat the same command.
          if (controller.value.isPlaying) {
            await controller.pause();
          } else {
            await controller.play();
          }
          if (mounted) setState(() {});
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  VideoPlayer(controller),
                  if (!playing)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
