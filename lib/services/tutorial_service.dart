import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TutorialTooltipPosition { above, below }

class TutorialStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final String? actionLabel;
  final EdgeInsets spotlightPadding;
  final TutorialTooltipPosition tooltipPosition;
  final VoidCallback? onStepStarted;

  const TutorialStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.actionLabel,
    this.spotlightPadding = const EdgeInsets.all(8),
    this.tooltipPosition = TutorialTooltipPosition.below,
    this.onStepStarted,
  });
}

class TutorialService extends ChangeNotifier {
  static final TutorialService _instance = TutorialService._internal();
  factory TutorialService() => _instance;
  TutorialService._internal();

  static const String _completionKey = 'parkiwell_main_tutorial_completed_v1';

  List<TutorialStep> _steps = const <TutorialStep>[];
  int _currentStepIndex = -1;
  int _lastAnnouncedStep = -1;

  bool get isActive =>
      _currentStepIndex >= 0 && _currentStepIndex < _steps.length;
  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => _steps.length;
  TutorialStep? get currentStep => isActive ? _steps[_currentStepIndex] : null;

  Future<bool> shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_completionKey) ?? false);
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completionKey, true);
  }

  Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completionKey);
  }

  bool _restartRequested = false;
  bool get restartRequested => _restartRequested;

  /// Asks the mounted TutorialOverlay (e.g. the Navbar's) to start the
  /// tutorial again without remounting the widget tree.
  void requestRestart() {
    _restartRequested = true;
    notifyListeners();
  }

  void consumeRestartRequest() {
    _restartRequested = false;
  }

  void start(List<TutorialStep> steps) {
    if (steps.isEmpty) return;
    _steps = List<TutorialStep>.from(steps);
    _currentStepIndex = 0;
    _lastAnnouncedStep = -1;
    _announceStepIfNeeded();
    notifyListeners();
  }

  Future<void> next() async {
    if (!isActive) return;
    _currentStepIndex += 1;
    if (_currentStepIndex >= _steps.length) {
      await complete();
      return;
    }
    _announceStepIfNeeded();
    notifyListeners();
  }

  Future<void> skip() async {
    await complete();
  }

  Future<void> complete() async {
    if (_steps.isNotEmpty) {
      await markCompleted();
    }
    _steps = const <TutorialStep>[];
    _currentStepIndex = -1;
    _lastAnnouncedStep = -1;
    notifyListeners();
  }

  void dismiss() {
    _steps = const <TutorialStep>[];
    _currentStepIndex = -1;
    _lastAnnouncedStep = -1;
    notifyListeners();
  }

  void _announceStepIfNeeded() {
    if (!isActive) return;
    if (_lastAnnouncedStep == _currentStepIndex) return;
    _lastAnnouncedStep = _currentStepIndex;
    _steps[_currentStepIndex].onStepStarted?.call();
  }
}
