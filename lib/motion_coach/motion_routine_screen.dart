import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:motion_engine/motion_engine.dart';

import '../singleton.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';
import 'motion_capture_driver.dart';
import 'motion_coach_screen.dart' show MotionCaptureDriverFactory;
import 'motion_coach_session.dart';
import 'motion_cue_speaker.dart';
import 'motion_demonstration_view.dart';
import 'motion_exercise_catalog.dart';
import 'motion_reference_library.dart';
import 'motion_routine_catalog.dart';
import 'motion_routine_controller.dart';
import 'motion_routine_results_screen.dart';
import 'motion_session_history.dart';
import 'motion_skeleton_overlay.dart';

enum _RoutineScreenPhase { initializing, ready, running, suspended, error }

/// Guided multi-exercise routine.
///
/// Unlike the single-exercise motion check, nothing is recorded: the camera
/// stream is consumed frame by frame and discarded, so no video file is ever
/// created. Only the engine's derived scores survive the session.
class MotionRoutineScreen extends StatefulWidget {
  const MotionRoutineScreen({
    super.key,
    required this.description,
    required this.routine,
    required this.library,
    this.driverFactory,
    this.cueSpeaker,
    this.history,
    this.onSessionLogged,
  });

  final MotionRoutineDescription description;
  final RoutineDefinition routine;
  final MotionReferenceLibrary library;
  final MotionCaptureDriverFactory? driverFactory;
  final MotionCueSpeaker? cueSpeaker;
  final MotionSessionHistory? history;

  /// Called once when a session completes, so it counts in the app's shared
  /// recovery tracking (weekly plan, history). Injectable for tests; the
  /// default logs through the app [Singleton].
  final Future<void> Function(MotionSessionRecord record)? onSessionLogged;

  @override
  State<MotionRoutineScreen> createState() => _MotionRoutineScreenState();
}

class _MotionRoutineScreenState extends State<MotionRoutineScreen>
    with WidgetsBindingObserver {
  late final MotionRoutineController _controller;
  late final MotionCueSpeaker _cueSpeaker;
  MotionCaptureDriver? _driver;
  _RoutineScreenPhase _phase = _RoutineScreenPhase.initializing;
  MotionDemonstrationLoop? _demonstration;
  String? _demonstrationExerciseId;
  int _handledRepSerial = 0;
  int _handledCueSerial = 0;
  bool _finishing = false;
  int _generation = 0;
  String _errorTitle = 'The guided routine is unavailable';
  String _errorBody = 'Please try again.';

  @override
  void initState() {
    super.initState();
    _controller = MotionRoutineController(
      routine: widget.routine,
      library: widget.library,
    );
    _cueSpeaker = widget.cueSpeaker ?? PlatformMotionCueSpeaker();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChanged);
    unawaited(_cueSpeaker.initialize());
    unawaited(_loadDemonstration());
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    unawaited(_cueSpeaker.dispose());
    unawaited(_driver?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_phase == _RoutineScreenPhase.suspended) unawaited(_initialize());
      return;
    }
    if (state != AppLifecycleState.resumed) unawaited(_suspend());
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.repSerial > _handledRepSerial) {
      _handledRepSerial = _controller.repSerial;
      HapticUtils.selectionClick();
    }
    final LiveExerciseCue? cue = _controller.cue;
    if (_controller.cueSerial > _handledCueSerial && cue != null) {
      _handledCueSerial = _controller.cueSerial;
      unawaited(_cueSpeaker.speak(cue.text));
    }
    if (_demonstrationExerciseId != _controller.currentStep.exerciseId) {
      unawaited(_loadDemonstration());
    }
    if (_controller.phase == MotionRoutinePhase.complete) {
      unawaited(_finish());
    }
    setState(() {});
  }

  Future<void> _loadDemonstration() async {
    final String exerciseId = _controller.currentStep.exerciseId;
    _demonstrationExerciseId = exerciseId;
    try {
      final MotionDemonstrationLoop loop = await widget.library
          .loadDemonstration(exerciseId);
      if (!mounted || _demonstrationExerciseId != exerciseId) return;
      setState(() => _demonstration = loop);
    } on Object {
      // The written instruction is the fallback; a missing guide animation
      // must not stop the routine. Guarded like the success path so a stale
      // failure can never clobber a newer step's loaded guide.
      if (!mounted || _demonstrationExerciseId != exerciseId) return;
      setState(() => _demonstration = null);
    }
  }

  Future<void> _initialize() async {
    final int generation = ++_generation;
    _controller.reset();
    final MotionCaptureDriver? previous = _driver;
    _driver = null;
    await previous?.dispose();
    if (!mounted || generation != _generation) return;

    setState(() => _phase = _RoutineScreenPhase.initializing);
    final MotionCaptureDriver driver =
        (widget.driverFactory ?? CameraMotionCaptureDriver.new)();
    _driver = driver;
    try {
      await driver.initialize(
        _controller.handleSample,
        onPersistentFailure: _onDetectorFailure,
      );
      if (!mounted || generation != _generation) {
        await driver.dispose();
        return;
      }
      setState(() => _phase = _RoutineScreenPhase.ready);
    } on CameraException catch (error) {
      await driver.dispose();
      if (!mounted || generation != _generation) return;
      final bool denied =
          error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted';
      setState(() {
        _phase = _RoutineScreenPhase.error;
        _errorTitle = denied
            ? 'Camera access is needed'
            : 'Camera could not start';
        _errorBody = denied
            ? 'Open your phone settings and allow Camera access for '
                  'ParkiWell, then return and try again.'
            : 'Close other apps using the camera, then try again.';
      });
    } catch (_) {
      await driver.dispose();
      if (!mounted || generation != _generation) return;
      setState(() {
        _phase = _RoutineScreenPhase.error;
        _errorTitle = 'The guided routine could not start';
        _errorBody =
            'The on-device motion model could not be prepared. Restart '
            'ParkiWell and try again.';
      });
    }
  }

  /// Pose detection has failed continuously; treat it like any other fatal
  /// startup problem rather than leaving the person on "Looking for you".
  void _onDetectorFailure() {
    if (!mounted || _phase == _RoutineScreenPhase.error) return;
    unawaited(_driver?.dispose());
    _driver = null;
    _controller.reset();
    setState(() {
      _phase = _RoutineScreenPhase.error;
      _errorTitle = 'Movement tracking stopped working';
      _errorBody =
          'The on-device motion model kept failing. Restart ParkiWell and '
          'try again.';
    });
  }

  Future<void> _suspend() async {
    if (_phase == _RoutineScreenPhase.suspended) return;
    ++_generation;
    _controller.reset();
    final MotionCaptureDriver? driver = _driver;
    _driver = null;
    await driver?.dispose();
    unawaited(_cueSpeaker.stop());
    if (mounted) setState(() => _phase = _RoutineScreenPhase.suspended);
  }

  void _start() {
    if (!_controller.isFramingReady) return;
    HapticUtils.mediumImpact();
    _handledRepSerial = 0;
    _handledCueSerial = 0;
    _controller.start();
    setState(() => _phase = _RoutineScreenPhase.running);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final Map<String, Object?>? evaluation = _controller.evaluation;
    HapticUtils.success();
    unawaited(_cueSpeaker.stop());
    final MotionCaptureDriver? driver = _driver;
    _driver = null;
    await driver?.dispose();
    if (evaluation == null || !mounted) return;

    // The evaluation is parsed exactly once. If the document itself cannot
    // be parsed there is nothing to show; anything downstream of a
    // successful parse (saving) failing must not cost the person their
    // results.
    final MotionSessionRecord record;
    try {
      record = MotionSessionRecord.fromEvaluation(
        evaluation,
        completedAt: DateTime.now(),
      );
    } on Object {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    bool saved = true;
    try {
      await (widget.history ?? MotionSessionHistory()).add(record);
    } on Object {
      saved = false;
    }
    // Count the completed session in the app's shared recovery tracking.
    // Best effort: a logging failure must not block the results screen.
    try {
      await (widget.onSessionLogged ?? _logToRecoveryTracking)(record);
    } on Object {
      // The coach's own history above is the authoritative record.
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MotionRoutineResultsScreen(
          description: widget.description,
          record: record,
          saved: saved,
        ),
      ),
    );
  }

  static Future<void> _logToRecoveryTracking(MotionSessionRecord record) =>
      Singleton().recordMotionCoachSession(
        routineId: record.routineId,
        title: 'Motion coach: ${record.routineName}',
        completedAt: record.completedAt,
      );

  Future<void> _confirmExit() async {
    if (_phase != _RoutineScreenPhase.running) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Stop this routine?'),
        content: const Text(
          'Your progress in this routine will be discarded. Nothing has been '
          'recorded or saved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: _phase != _RoutineScreenPhase.running,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(widget.description.title),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => unawaited(_confirmExit()),
          ),
        ),
        body: LiquidBackground(
          child: SafeArea(
            top: false,
            child: switch (_phase) {
              _RoutineScreenPhase.error => _buildMessage(
                context,
                icon: Icons.error_outline_rounded,
                title: _errorTitle,
                body: _errorBody,
                actionLabel: 'Try again',
                onAction: () => unawaited(_initialize()),
              ),
              _RoutineScreenPhase.suspended => _buildMessage(
                context,
                icon: Icons.pause_circle_outline_rounded,
                title: 'Routine paused',
                body:
                    'ParkiWell released the camera when you left the app. '
                    'Start again when you are ready.',
                actionLabel: 'Resume',
                onAction: () => unawaited(_initialize()),
              ),
              _RoutineScreenPhase.initializing => const Center(
                child: CircularProgressIndicator(),
              ),
              _RoutineScreenPhase.ready ||
              _RoutineScreenPhase.running => _buildSession(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSession(BuildContext context) {
    final colors = context.colors;
    final bool running = _phase == _RoutineScreenPhase.running;
    final MotionExerciseDefinition exercise = _controller.currentExercise;

    return Column(
      children: <Widget>[
        LinearProgressIndicator(
          value: _controller.progress,
          minHeight: 6,
          backgroundColor: colors.primary.withValues(alpha: 0.12),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Step ${_controller.stepIndex + 1} of '
                  '${_controller.stepCount} · ${exercise.postureLabel}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  exercise.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  running ? exercise.instructions : exercise.setupHint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _buildStage(context, running: running),
                const SizedBox(height: 16),
                if (running)
                  _buildLiveStatus(context)
                else
                  _buildFramingStatus(context),
                const SizedBox(height: 16),
                if (!running)
                  FilledButton.icon(
                    onPressed: _controller.isFramingReady ? _start : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    label: Text(
                      _controller.isFramingReady
                          ? 'Start routine'
                          : 'Waiting for a clear view',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Camera preview beside the reference figure, so the person can compare
  /// what they are doing with what the exercise asks for.
  Widget _buildStage(BuildContext context, {required bool running}) {
    final colors = context.colors;
    final MotionDemonstrationLoop? demonstration = _demonstration;
    return SizedBox(
      height: 260,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ColoredBox(
                color: colors.surface,
                child: _driver?.isInitialized == true
                    ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: 260 / _driver!.aspectRatio,
                          height: 260,
                          // The overlay shares the preview's exact coordinate
                          // box so normalized landmarks map straight onto it.
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              _driver!.buildPreview(),
                              MotionSkeletonOverlay(
                                frame: _controller.skeleton,
                                mirrored: true,
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ModernCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: <Widget>[
                  Text(
                    'Guide',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: demonstration == null
                        ? const SizedBox.expand()
                        : MotionDemonstrationView(
                            key: ValueKey<String>(demonstration.exerciseId),
                            loop: demonstration,
                            color: colors.primary,
                            playing:
                                _controller.phase !=
                                MotionRoutinePhase.complete,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFramingStatus(BuildContext context) {
    final colors = context.colors;
    final bool ready = _controller.isFramingReady;
    final String message = switch (_controller.framingStatus) {
      MotionFramingStatus.ready => 'You are in frame. Start when ready.',
      MotionFramingStatus.multiplePeople =>
        'More than one person is in view. The routine needs a single person '
            'in frame.',
      MotionFramingStatus.showMoreBody =>
        'Move so your head, both hands, and both hips are inside the frame.',
      MotionFramingStatus.moveCloser =>
        'Move a little closer to the phone, or lift it higher.',
      MotionFramingStatus.lookingForPerson => 'Looking for you…',
    };
    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      backgroundColor: (ready ? colors.success : colors.warning).withValues(
        alpha: 0.11,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            ready
                ? Icons.check_circle_rounded
                : Icons.center_focus_weak_rounded,
            color: ready ? colors.success : colors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatus(BuildContext context) {
    final colors = context.colors;
    if (_controller.phase == MotionRoutinePhase.rest) {
      return ModernCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(20),
        backgroundColor: colors.primary.withValues(alpha: 0.1),
        child: Column(
          children: <Widget>[
            Text(
              'Rest',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${_controller.restRemainingSeconds.ceil()} seconds',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
          ],
        ),
      );
    }

    final ExerciseRepScore? score = _controller.lastRepScore;
    final LiveExerciseCue? cue = _controller.cue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ModernCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Repetitions',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${_controller.completedRepetitions} of '
                      '${_controller.targetRepetitions}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (score != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      'Last movement',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${score.overall.round()}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.primary,
                          ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (cue != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            label: 'Motion coach: ${cue.text}',
            child: ModernCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(18),
              backgroundColor: colors.primary.withValues(alpha: 0.12),
              child: Text(
                cue.text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: colors.warning),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
