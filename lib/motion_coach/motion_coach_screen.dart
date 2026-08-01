import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:motion_engine/motion_engine.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';
import 'motion_analysis.dart';
import 'motion_capture_driver.dart';
import 'motion_coach_preferences.dart';
import 'motion_coach_results_screen.dart';
import 'motion_coach_session.dart';
import 'motion_cue_speaker.dart';
import 'motion_exercise_catalog.dart';
import 'motion_reference_library.dart';

typedef MotionCaptureDriverFactory = MotionCaptureDriver Function();

class MotionCoachOutcome {
  const MotionCoachOutcome({required this.videoPath, required this.analysis});

  final String videoPath;
  final MotionAnalysisResult analysis;
}

enum _CapturePhase {
  initializing,
  framing,
  recording,
  analyzing,
  suspended,
  error,
}

class MotionCoachScreen extends StatefulWidget {
  /// [library] must already have this exercise's template loaded — the live
  /// coach's thresholds come from it and are needed synchronously here.
  const MotionCoachScreen({
    super.key,
    required this.library,
    this.driverFactory,
    this.analyzer = const MotionCoachAnalyzer(),
    this.exercise = seatedArmRaiseExercise,
    this.cueSpeaker,
    this.preferences,
  });

  final MotionReferenceLibrary library;
  final MotionCaptureDriverFactory? driverFactory;
  final MotionCoachAnalyzer analyzer;
  final MotionExerciseDefinition exercise;
  final MotionCueSpeaker? cueSpeaker;

  /// Cue delivery preferences; defaults to the shared app-wide instance.
  final MotionCoachPreferences? preferences;

  @override
  State<MotionCoachScreen> createState() => _MotionCoachScreenState();
}

class _MotionCoachScreenState extends State<MotionCoachScreen>
    with WidgetsBindingObserver {
  static const Duration _maximumDuration = Duration(minutes: 3);

  late final MotionCoachSession _session;
  late final MotionCueSpeaker _cueSpeaker;
  late final MotionCoachPreferences _preferences;
  final Stopwatch _recordingClock = Stopwatch();
  MotionCaptureDriver? _driver;
  Timer? _timer;
  _CapturePhase _phase = _CapturePhase.initializing;
  Duration _elapsed = Duration.zero;
  String _errorTitle = 'Motion check is unavailable';
  String _errorBody = 'Please try again.';
  int _generation = 0;
  int _handledLiveRepSerial = 0;
  int _handledLiveCueSerial = 0;
  bool _finishingRecording = false;
  LiveExerciseCue? _spokenCue;

  bool get _isBusy =>
      _phase == _CapturePhase.recording || _phase == _CapturePhase.analyzing;

  @override
  void initState() {
    super.initState();
    _session = MotionCoachSession(
      liveCoach: LiveExerciseCoach(
        widget.exercise.engineSpec,
        widget.library.configFor(widget.exercise.exerciseId),
      ),
    );
    _cueSpeaker = widget.cueSpeaker ?? PlatformMotionCueSpeaker();
    _preferences = widget.preferences ?? MotionCoachPreferences.shared;
    if (!_preferences.isLoaded) unawaited(_preferences.load());
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSessionChanged);
    unawaited(_cueSpeaker.initialize());
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _session
      ..removeListener(_onSessionChanged)
      ..dispose();
    unawaited(_cueSpeaker.dispose());
    unawaited(_driver?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_phase == _CapturePhase.suspended) {
        unawaited(_initialize());
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_suspend());
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final LiveExerciseCue? liveCue = _session.liveCue;
    if (_session.liveRepSerial > _handledLiveRepSerial) {
      _handledLiveRepSerial = _session.liveRepSerial;
      if (_preferences.hapticsEnabled) HapticUtils.selectionClick();
    }
    if (_session.liveCueSerial > _handledLiveCueSerial && liveCue != null) {
      _handledLiveCueSerial = _session.liveCueSerial;
      _spokenCue = liveCue;
      if (_preferences.speechEnabled) {
        unawaited(_cueSpeaker.speak(liveCue.text));
      }
    } else if (liveCue == null && _spokenCue != null) {
      _spokenCue = null;
      unawaited(_cueSpeaker.stop());
    }
    setState(() {});
  }

  Future<void> _initialize() async {
    final int generation = ++_generation;
    _finishingRecording = false;
    _timer?.cancel();
    _recordingClock
      ..stop()
      ..reset();
    _session.reset();
    final MotionCaptureDriver? previous = _driver;
    _driver = null;
    await previous?.dispose();
    if (!mounted || generation != _generation) return;

    setState(() {
      _phase = _CapturePhase.initializing;
      _elapsed = Duration.zero;
    });
    final MotionCaptureDriver driver =
        (widget.driverFactory ?? CameraMotionCaptureDriver.new)();
    _driver = driver;
    try {
      await driver.initialize(
        _session.handleSample,
        onPersistentFailure: _onDetectorFailure,
      );
      if (!mounted || generation != _generation) {
        await driver.dispose();
        return;
      }
      setState(() => _phase = _CapturePhase.framing);
    } on CameraException catch (error) {
      await driver.dispose();
      if (!mounted || generation != _generation) return;
      _showCameraError(error);
    } catch (_) {
      await driver.dispose();
      if (!mounted || generation != _generation) return;
      setState(() {
        _phase = _CapturePhase.error;
        _errorTitle = 'Motion check could not start';
        _errorBody =
            'The on-device motion model could not be prepared. Restart '
            'ParkiWell and try again.';
      });
    }
  }

  /// Pose detection has failed continuously; surface it instead of letting
  /// the person wait on framing that can never become ready.
  void _onDetectorFailure() {
    if (!mounted || _phase == _CapturePhase.error) return;
    final MotionCaptureDriver? driver = _driver;
    _driver = null;
    unawaited(driver?.cancelRecording().catchError((_) {}));
    unawaited(driver?.dispose());
    _timer?.cancel();
    _recordingClock
      ..stop()
      ..reset();
    _session.reset();
    setState(() {
      _phase = _CapturePhase.error;
      _errorTitle = 'Movement tracking stopped working';
      _errorBody =
          'The on-device motion model kept failing. Restart ParkiWell and '
          'try again.';
    });
  }

  void _showCameraError(CameraException error) {
    final bool denied =
        error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt' ||
        error.code == 'CameraAccessRestricted';
    setState(() {
      _phase = _CapturePhase.error;
      _errorTitle = denied
          ? 'Camera access is needed'
          : 'Camera could not start';
      _errorBody = denied
          ? 'Open your phone settings and allow Camera access for ParkiWell, '
                'then return and try again.'
          : 'Close other apps using the camera, then try again.';
    });
  }

  Future<void> _suspend() async {
    if (_phase == _CapturePhase.suspended) return;
    // A finish already owns the driver and is about to drain the session's
    // frames; resetting or disposing here would wipe the just-completed
    // recording mid-finalization and delete its file under the analyzer.
    if (_finishingRecording) return;
    ++_generation;
    _timer?.cancel();
    _recordingClock
      ..stop()
      ..reset();
    _session.reset();
    final MotionCaptureDriver? driver = _driver;
    _driver = null;
    try {
      await driver?.cancelRecording();
    } catch (_) {
      // Lifecycle cleanup continues even if the platform already stopped.
    }
    await driver?.dispose();
    if (mounted) {
      setState(() {
        _phase = _CapturePhase.suspended;
        _elapsed = Duration.zero;
      });
    }
  }

  Future<void> _startRecording() async {
    final MotionCaptureDriver? driver = _driver;
    if (driver == null ||
        _phase != _CapturePhase.framing ||
        !_session.isReady) {
      return;
    }
    HapticUtils.mediumImpact();
    _handledLiveRepSerial = 0;
    _handledLiveCueSerial = 0;
    _spokenCue = null;
    _session.beginRecording();
    try {
      await driver.startRecording();
      if (!mounted) return;
      _recordingClock
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        final Duration elapsed = _recordingClock.elapsed;
        if (elapsed >= _maximumDuration) {
          unawaited(_finishRecording());
          return;
        }
        if (elapsed.inSeconds != _elapsed.inSeconds) {
          setState(() => _elapsed = elapsed);
        }
      });
      setState(() => _phase = _CapturePhase.recording);
    } on CameraException catch (error) {
      _session.reset();
      if (mounted) _showCameraError(error);
    }
  }

  Future<void> _finishRecording() async {
    final MotionCaptureDriver? driver = _driver;
    if (driver == null || _phase != _CapturePhase.recording) return;
    // Claim the driver and mark the finish before the first await so a
    // concurrent lifecycle suspend can neither reset the buffered frames
    // nor double-stop and delete the recording being finalized.
    _finishingRecording = true;
    _driver = null;
    _timer?.cancel();
    _recordingClock.stop();
    setState(() => _phase = _CapturePhase.analyzing);

    String? videoPath;
    try {
      videoPath = await driver.stopRecording();
      final frames = _session.finishAndDrain();
      final int width = _session.frameWidth;
      final int height = _session.frameHeight;
      await driver.dispose();
      final MotionAnalysisResult analysis = await widget.analyzer.analyze(
        frames: frames,
        width: width,
        height: height,
        exercise: widget.exercise,
      );
      if (!mounted) {
        await _deleteVideo(videoPath);
        return;
      }
      HapticUtils.success();
      final MotionCoachResultAction? action = await Navigator.of(context)
          .push<MotionCoachResultAction>(
            MaterialPageRoute<MotionCoachResultAction>(
              builder: (_) => MotionCoachResultsScreen(result: analysis),
            ),
          );
      if (!mounted) return;
      if (action == MotionCoachResultAction.useRecording) {
        Navigator.of(
          context,
        ).pop(MotionCoachOutcome(videoPath: videoPath, analysis: analysis));
        return;
      }
      await _deleteVideo(videoPath);
      await _initialize();
    } catch (_) {
      _session.finishAndDrain();
      await driver.dispose();
      if (videoPath != null) await _deleteVideo(videoPath);
      _finishingRecording = false;
      if (!mounted) return;
      setState(() {
        _phase = _CapturePhase.error;
        _errorTitle = 'The recording could not be analyzed';
        _errorBody =
            'Nothing was uploaded. Check available storage and try again.';
      });
    }
  }

  Future<void> _confirmCancel({required bool exitAfter}) async {
    if (_phase != _CapturePhase.recording) {
      if (exitAfter && mounted) Navigator.of(context).pop();
      return;
    }
    final bool? cancel = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Discard this recording?'),
        content: const Text(
          'The current video and motion frames will be deleted from this '
          'device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep recording'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;

    _timer?.cancel();
    _recordingClock
      ..stop()
      ..reset();
    final MotionCaptureDriver? driver = _driver;
    _driver = null;
    _session.reset();
    setState(() => _phase = _CapturePhase.analyzing);
    try {
      await driver?.cancelRecording();
    } finally {
      await driver?.dispose();
    }
    if (!mounted) return;
    if (exitAfter) {
      Navigator.of(context).pop();
    } else {
      await _initialize();
    }
  }

  Future<void> _deleteVideo(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _handleBack() {
    if (_phase == _CapturePhase.recording) {
      unawaited(_confirmCancel(exitAfter: true));
      return;
    }
    if (_phase == _CapturePhase.analyzing) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope<Object?>(
      canPop: !_isBusy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Motion check'),
        ),
        body: LiquidBackground(
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double cameraHeight = math.min(
                  420,
                  math.max(270, constraints.maxHeight * 0.52),
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.exercise.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.exercise.instructions,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: cameraHeight,
                        child: ModernCard(
                          margin: EdgeInsets.zero,
                          padding: EdgeInsets.zero,
                          borderRadius: 22,
                          child: _buildCameraArea(context),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildGuidance(context),
                      const SizedBox(height: 14),
                      _buildActions(context),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea(BuildContext context) {
    final colors = context.colors;
    final MotionCaptureDriver? driver = _driver;
    if ((_phase == _CapturePhase.framing ||
            _phase == _CapturePhase.recording) &&
        driver?.isInitialized == true) {
      return Semantics(
        label:
            'Front camera preview. Keep your face, shoulders, wrists, and hips '
            'visible.',
        image: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: ExcludeSemantics(child: driver!.buildPreview()),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _session.isReady
                        ? colors.success
                        : Colors.white.withValues(alpha: 0.65),
                    width: _session.isReady ? 3 : 2,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: _TrackingPill(
                status: _session.framingStatus,
                recording: _phase == _CapturePhase.recording,
              ),
            ),
            if (_phase == _CapturePhase.recording)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_session.liveRepCount} complete',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (_phase == _CapturePhase.recording)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(_elapsed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_phase == _CapturePhase.recording && _session.liveCue != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 62,
                child: Semantics(
                  liveRegion: true,
                  label: 'Motion coach: ${_session.liveCue!.text}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.8),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      _session.liveCue!.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final (IconData icon, String title, String body) = switch (_phase) {
      _CapturePhase.error => (
        Icons.camera_alt_outlined,
        _errorTitle,
        _errorBody,
      ),
      _CapturePhase.suspended => (
        Icons.pause_circle_outline_rounded,
        'Motion check paused',
        'Return to ParkiWell to restart the camera safely.',
      ),
      _CapturePhase.analyzing => (
        Icons.auto_graph_rounded,
        'Reviewing on this device',
        'Your video and motion frames are staying private.',
      ),
      _ => (
        Icons.camera_alt_outlined,
        'Preparing the camera',
        'Loading the on-device motion model…',
      ),
    };
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_phase == _CapturePhase.initializing ||
                  _phase == _CapturePhase.analyzing)
                CircularProgressIndicator(color: colors.primary)
              else
                Icon(icon, size: 44, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidance(BuildContext context) {
    final colors = context.colors;
    final String guidance = switch (_session.framingStatus) {
      MotionFramingStatus.lookingForPerson =>
        'Sit where the camera can see you.',
      MotionFramingStatus.multiplePeople =>
        'Keep only one person in the camera view.',
      MotionFramingStatus.showMoreBody =>
        'Keep your face, shoulders, wrists, and hips visible.',
      MotionFramingStatus.moveCloser =>
        'Move the phone a little closer and keep it steady.',
      MotionFramingStatus.ready =>
        _phase == _CapturePhase.recording
            ? (_session.liveCue?.text ??
                  'Complete ${widget.exercise.recordingRepetitionLabel} '
                      'comfortable raises, then finish.')
            : 'You’re in frame. Start when you feel ready.',
    };
    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _session.isReady
                    ? Icons.check_circle_rounded
                    : Icons.center_focus_weak_rounded,
                color: _session.isReady ? colors.success : colors.secondary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  guidance,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  color: colors.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Use a stable chair and a comfortable range. Stop if you '
                    'feel pain, dizzy, or unsteady.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    if (_phase == _CapturePhase.error) {
      return SizedBox(
        height: 54,
        child: FilledButton.icon(
          onPressed: _initialize,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
    }
    if (_phase == _CapturePhase.recording) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _finishRecording,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Finish and review'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => _confirmCancel(exitAfter: false),
              child: const Text('Cancel recording'),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: _phase == _CapturePhase.framing && _session.isReady
            ? _startRecording
            : null,
        icon: const Icon(Icons.fiber_manual_record_rounded),
        label: Text(
          _phase == _CapturePhase.analyzing ? 'Reviewing…' : 'Start movement',
        ),
      ),
    );
  }
}

class _TrackingPill extends StatelessWidget {
  const _TrackingPill({required this.status, required this.recording});

  final MotionFramingStatus status;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bool ready = status == MotionFramingStatus.ready;
    final String text = ready
        ? (recording ? 'Tracking movement' : 'Ready')
        : switch (status) {
            MotionFramingStatus.lookingForPerson => 'Move into view',
            MotionFramingStatus.multiplePeople => 'Keep one person in view',
            MotionFramingStatus.showMoreBody => 'Show more of your upper body',
            MotionFramingStatus.moveCloser => 'Move a little closer',
            MotionFramingStatus.ready => 'Ready',
          };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: (ready ? colors.success : Colors.white).withValues(
              alpha: 0.58,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.check_circle_rounded : Icons.center_focus_weak,
              color: ready ? colors.success : Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final int minutes = duration.inMinutes;
  final int seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
