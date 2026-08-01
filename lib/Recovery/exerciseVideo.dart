import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_coach_screen.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';
import 'package:parkiwell/motion_coach/motion_reference_library.dart';
import 'package:parkiwell/singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/tutorial_targets.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_button.dart';
import '../widgets/modern_card.dart';
import '../widgets/session_completion_bar.dart';
import '../widgets/tutorial_overlay.dart';

class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({super.key});

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  static const String _motionCoachConsentKey =
      'motion_coach_mediapipe_consent_v1';

  final singleton = Singleton();
  final ImagePicker _picker = ImagePicker();

  VideoPlayerController? _recordingController;
  WebViewController? _webViewController;
  String? _videoId;
  MotionExerciseDefinition? _motionExercise;
  bool _isVideoLoading = true;
  bool _isShowingMotionDemo = false;

  String? _recordedVideoPath;
  bool _isRecordingVideo = false;
  bool _isMotionCoachOpening = false;

  bool get _hasRecording => _recordedVideoPath != null;
  String get _youtubeUrl {
    final String videoId = _videoId ?? singleton.currentURL;
    return Uri.https('www.youtube.com', '/watch', <String, String>{
      'v': videoId,
    }).toString();
  }

  @override
  void initState() {
    super.initState();
    _videoId = singleton.normalizeYouTubeVideoId(singleton.currentURL);
    _motionExercise = motionExerciseForVideo(_videoId);
    if (_videoId != null && !kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (!mounted) return;
              setState(() => _isVideoLoading = true);
            },
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _isVideoLoading = false);
            },
            onWebResourceError: (WebResourceError error) {
              if (error.isForMainFrame != true) return;
              if (!mounted) return;
              setState(() => _webViewController = null);
            },
          ),
        )
        ..loadRequest(
          _fullSessionEmbedUri(_videoId!),
          headers: youTubeEmbeddedPlayerHeaders,
        );
    } else {
      _isVideoLoading = false;
    }
  }

  Uri _fullSessionEmbedUri(String videoId) {
    return Uri.https('www.youtube.com', '/embed/$videoId', <String, String>{
      'playsinline': '1',
      'controls': '1',
      'rel': '0',
    });
  }

  Future<void> _loadGuidedVideo({required bool demoOnly}) async {
    final String? videoId = _videoId;
    if (videoId == null) return;
    final MotionExerciseDefinition? exercise = _motionExercise;
    if (demoOnly && exercise == null) return;
    HapticUtils.lightImpact();
    final WebViewController? controller = _webViewController;
    if (controller == null) {
      if (!demoOnly) return;
      await launchUrl(
        exercise!.videoSegment!.youtubeWatchUri(demoOnly: true),
        mode: LaunchMode.inAppBrowserView,
      );
      return;
    }

    setState(() {
      _isShowingMotionDemo = demoOnly;
      _isVideoLoading = true;
    });
    final Uri uri = demoOnly
        ? exercise!.videoSegment!.youtubeEmbedUri(demoOnly: true)
        : _fullSessionEmbedUri(videoId);
    await controller.loadRequest(uri, headers: youTubeEmbeddedPlayerHeaders);
    if (!mounted) return;
    final BuildContext? playerContext =
        TutorialTargets.exerciseVideoPlayerKey.currentContext;
    if (playerContext != null && playerContext.mounted) {
      await Scrollable.ensureVisible(
        playerContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
  }

  @override
  void dispose() {
    _recordingController?.dispose();
    unawaited(_deleteRecordingFile(_recordedVideoPath));
    super.dispose();
  }

  Future<void> _openInAppBrowser() async {
    if (_videoId == null) return;
    final uri = Uri.parse(_youtubeUrl);
    await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    );
  }

  Future<void> _openInYouTube() async {
    if (_videoId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This video link appears invalid.'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }

    final uri = Uri.parse(_youtubeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unable to open YouTube link'),
        backgroundColor: context.colors.error,
      ),
    );
  }

  Future<void> _setRecording(String path) async {
    final previous = _recordingController;
    final previousPath = _recordedVideoPath;
    final next = VideoPlayerController.file(File(path));
    await next.initialize();
    await next.setLooping(true);

    if (!mounted) {
      await next.dispose();
      if (previousPath != path) {
        await _deleteRecordingFile(path);
      }
      return;
    }

    await previous?.dispose();
    if (previousPath != path) {
      await _deleteRecordingFile(previousPath);
    }
    if (!mounted) {
      await next.dispose();
      await _deleteRecordingFile(path);
      return;
    }
    setState(() {
      _recordedVideoPath = path;
      _recordingController = next;
    });
  }

  Future<void> _recordVideo() async {
    if (_isRecordingVideo) return;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recording preview is available in the iOS and Android app.',
          ),
        ),
      );
      return;
    }

    HapticUtils.mediumImpact();
    setState(() => _isRecordingVideo = true);

    try {
      final video = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxDuration: const Duration(minutes: 3),
      );

      if (video == null) return;

      await _setRecording(video.path);
      if (!mounted) return;

      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Recording captured successfully.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticUtils.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRecordingVideo = false);
      }
    }
  }

  Future<void> _clearRecording() async {
    HapticUtils.lightImpact();
    final controller = _recordingController;
    final path = _recordedVideoPath;
    setState(() {
      _recordingController = null;
      _recordedVideoPath = null;
    });
    await controller?.dispose();
    await _deleteRecordingFile(path);
  }

  Future<void> _deleteRecordingFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _openMotionCoach() async {
    if (_isMotionCoachOpening || kIsWeb) return;
    final MotionExerciseDefinition? exercise = _motionExercise;
    if (exercise == null) return;
    HapticUtils.mediumImpact();
    setState(() => _isMotionCoachOpening = true);
    try {
      if (!await _ensureMotionCoachConsent() || !mounted) return;
      // The live coach reads its thresholds from the exercise template, so
      // the asset has to be decoded before the capture screen is built.
      final MotionReferenceLibrary library = MotionReferenceLibrary.shared;
      await library.templateFor(exercise.exerciseId);
      if (!mounted) return;
      final outcome = await Navigator.of(context).push<MotionCoachOutcome>(
        MaterialPageRoute<MotionCoachOutcome>(
          builder: (_) =>
              MotionCoachScreen(library: library, exercise: exercise),
        ),
      );
      if (outcome == null || !mounted) return;
      await _setRecording(outcome.videoPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Motion check added to your private recording.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      HapticUtils.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Motion check could not open. Please try again.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isMotionCoachOpening = false);
      }
    }
  }

  Future<bool> _ensureMotionCoachConsent() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_motionCoachConsentKey) == true) return true;
    if (!mounted) return false;

    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Motion check privacy'),
        content: const Text(
          'Your camera images, recording, and pose landmarks are processed '
          'on this device. Google MediaPipe may receive performance and usage '
          'metrics about its on-device API, but not your images, video, or '
          'pose landmarks.\n\n'
          'Motion check offers general movement observations. It is not a '
          'diagnosis or medical assessment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    await preferences.setBool(_motionCoachConsentKey, true);
    return true;
  }

  Future<int> _recordSession(DateTime completedAt) async {
    final videoId = _videoId ?? singleton.currentURL;
    final normalized = singleton.normalizeYouTubeVideoId(videoId);
    if (normalized == null) {
      throw StateError('Invalid exercise link');
    }
    return singleton.recordPhysicalExerciseSession(
      normalized,
      completedAt: completedAt,
    );
  }

  void _showReviewDialog() {
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review your recording',
                style: Theme.of(
                  c,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Use the preview as a private self-check. ParkiWell does not score or diagnose your movement.',
                style: Theme.of(c).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              const _ReviewCue(
                icon: Icons.speed_rounded,
                text: 'Did the pace feel controlled and comfortable?',
              ),
              const SizedBox(height: 12),
              const _ReviewCue(
                icon: Icons.accessibility_new_rounded,
                text: 'Could you move through a comfortable range?',
              ),
              const SizedBox(height: 12),
              const _ReviewCue(
                icon: Icons.favorite_outline_rounded,
                text:
                    'Stop and contact your care team if anything felt unsafe.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ModernButton(
                  text: 'Close',
                  onPressed: () => Navigator.pop(c),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final exerciseData = singleton.exercises[singleton.currentURL];

    if (exerciseData == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Exercise',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Container(
          color: colors.background,
          child: const Center(child: Text('Video not found')),
        ),
      );
    }

    final source = exerciseData.length > 3 ? exerciseData[3] : '';
    final MotionExerciseDefinition? motionExercise = _motionExercise;
    final MotionExerciseVideoSegment? motionSegment =
        motionExercise?.videoSegment;
    final sessionCount = singleton.exerciseSessionCountForVideo(
      singleton.currentURL,
    );

    return TutorialOverlay(
      steps: const [],
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              HapticUtils.lightImpact();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            'Exercise',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Open in YouTube',
              onPressed: () {
                HapticUtils.lightImpact();
                _openInYouTube();
              },
              icon: Icon(
                Icons.open_in_new_rounded,
                color: colors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LiquidBackground(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exerciseData[0],
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ModernCard(
                  padding: const EdgeInsets.all(14),
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session focus',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colors.textTertiary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        exerciseData[1],
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      if (source.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          source,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.textTertiary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ondemand_video_outlined,
                      size: 18,
                      color: colors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isShowingMotionDemo && motionSegment != null
                          ? 'Short demo · ${motionSegment.demoTimeRangeLabel}'
                          : 'Guided movement session',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                (_webViewController != null)
                    ? RepaintBoundary(
                        child: Container(
                          key: TutorialTargets.exerciseVideoPlayerKey,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: WebViewWidget(
                                    controller: _webViewController!,
                                  ),
                                ),
                                if (_isVideoLoading)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: colors.surface.withValues(
                                        alpha: 0.92,
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: colors.primary,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'Loading video...',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: colors.textSecondary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ModernCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kIsWeb
                                  ? 'Continue in YouTube'
                                  : 'Unable to load video in-app',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              kIsWeb
                                  ? 'Guided videos open in YouTube on the web. Your completion control stays here when you return.'
                                  : 'Open this exercise directly in YouTube.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            if (kIsWeb)
                              SizedBox(
                                width: double.infinity,
                                child: ModernButton(
                                  text: 'Play video',
                                  icon: Icons.open_in_new_rounded,
                                  onPressed: _openInYouTube,
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: ModernButton(
                                      text: 'Play in App',
                                      icon: Icons.ondemand_video_rounded,
                                      onPressed: _openInAppBrowser,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ModernButton(
                                      text: 'Open YouTube',
                                      isOutlined: true,
                                      icon: Icons.open_in_new_rounded,
                                      onPressed: _openInYouTube,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                if (_isShowingMotionDemo &&
                    motionExercise != null &&
                    motionSegment != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${motionExercise.title} · '
                          '${motionSegment.demonstrationRepetitions} guided '
                          'repetitions',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            unawaited(_loadGuidedVideo(demoOnly: false)),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Full session'),
                      ),
                    ],
                  ),
                ],
                if (!kIsWeb) ...[
                  const SizedBox(height: 24),
                  if (motionCoachEnabled &&
                      motionExercise != null &&
                      motionSegment != null) ...[
                    SectionHeading(
                      title: 'Motion check',
                      description:
                          'Watch the ${motionSegment.demoDurationSeconds}-second '
                          'example, then try the movement with private, '
                          'on-device observations.',
                    ),
                    const SizedBox(height: 12),
                    ModernCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      backgroundColor: colors.secondary.withValues(alpha: 0.08),
                      border: Border.all(
                        color: colors.secondary.withValues(alpha: 0.24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: colors.secondary.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  Icons.accessibility_new_rounded,
                                  color: colors.secondary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      motionExercise.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Record '
                                      '${motionExercise.recordingRepetitionLabel} '
                                      'comfortable raises. Your video and pose '
                                      'landmarks stay on this device.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colors.textSecondary,
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ModernButton(
                              text: _isShowingMotionDemo
                                  ? 'Replay short demo'
                                  : 'Watch short demo',
                              icon: Icons.play_circle_outline_rounded,
                              isOutlined: true,
                              onPressed: () =>
                                  unawaited(_loadGuidedVideo(demoOnly: true)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ModernButton(
                              text: 'Try motion check',
                              icon: Icons.camera_alt_rounded,
                              isLoading: _isMotionCoachOpening,
                              onPressed: _openMotionCoach,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const SectionHeading(
                    title: 'Practice recording',
                    description:
                        'Record a private preview to compare your movement with the guided session.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ModernButton(
                          text: _hasRecording ? 'Re-record' : 'Record Yourself',
                          icon: Icons.videocam_rounded,
                          isLoading: _isRecordingVideo,
                          onPressed: _recordVideo,
                        ),
                      ),
                      if (_hasRecording) ...[
                        const SizedBox(width: 10),
                        ModernIconButton(
                          icon: Icons.delete_outline_rounded,
                          backgroundColor: colors.error,
                          onPressed: () => unawaited(_clearRecording()),
                        ),
                      ],
                    ],
                  ),
                  if (_recordingController != null &&
                      _recordingController!.value.isInitialized) ...[
                    const SizedBox(height: 14),
                    ModernCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Recording',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio:
                                  _recordingController!.value.aspectRatio,
                              child: VideoPlayer(_recordingController!),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                HapticUtils.lightImpact();
                                final controller = _recordingController;
                                if (controller == null) return;
                                if (controller.value.isPlaying) {
                                  controller.pause();
                                } else {
                                  controller.play();
                                }
                                setState(() {});
                              },
                              icon: Icon(
                                _recordingController!.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _recordingController!.value.isPlaying
                                    ? 'Pause Preview'
                                    : 'Play Preview',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_hasRecording) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showReviewDialog,
                        icon: const Icon(Icons.fact_check_outlined, size: 19),
                        label: const Text('Review recording'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: SessionCompletionBar(
          sessionCount: sessionCount,
          title: exerciseData[0],
          typeLabel: 'Movement',
          duration: exerciseData.length > 2 ? exerciseData[2] : '',
          icon: Icons.accessibility_new_rounded,
          accent: colors.secondary,
          onLog: _recordSession,
        ),
      ),
    );
  }
}

class _ReviewCue extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ReviewCue({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
