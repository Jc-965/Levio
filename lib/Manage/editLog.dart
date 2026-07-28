import 'package:flutter/material.dart';

import '../services/tutorial_targets.dart';
import '../singleton.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/date_time_controls.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/tutorial_overlay.dart';

enum _WhenPreset { now, today, custom }

class EditLogScreen extends StatefulWidget {
  const EditLogScreen({super.key});

  @override
  State<EditLogScreen> createState() => _EditLogScreenState();
}

class _EditLogScreenState extends State<EditLogScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _severityOptions = <String>[
    'Very Mild',
    'Mild',
    'Moderate',
    'Severe',
    'Very Severe',
  ];
  static const List<String> _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final singleton = Singleton();
  final _symptomController = TextEditingController();
  final _symptomFocus = FocusNode();

  late final AnimationController _introController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  DateTime _selectedDateTime = DateTime.now();
  String _selectedSeverity = 'Moderate';
  _WhenPreset _selectedPreset = _WhenPreset.now;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _introController = AnimationController(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      vsync: this,
    )..forward();
    _fade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(_fade);
  }

  @override
  void dispose() {
    _introController.dispose();
    _symptomController.dispose();
    _symptomFocus.dispose();
    super.dispose();
  }

  Color _severityColor(String severity, AppColors colors) {
    if (severity == 'Very Mild' || severity == 'Mild') return colors.success;
    if (severity == 'Moderate') return colors.warning;
    return colors.error;
  }

  String _formatDisplayDate(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _formatDisplayTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  String _formatStorageTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$hour:$minute, $day ${_months[value.month - 1]} ${value.year}';
  }

  void _selectPreset(_WhenPreset preset) {
    final now = DateTime.now();
    final DateTime next;
    switch (preset) {
      case _WhenPreset.now:
        next = now;
      case _WhenPreset.today:
        final selectedTime = TimeOfDay.fromDateTime(_selectedDateTime);
        final candidate = DateTime(
          now.year,
          now.month,
          now.day,
          selectedTime.hour,
          selectedTime.minute,
        );
        next = candidate.isAfter(now) ? now : candidate;
      case _WhenPreset.custom:
        _pickDate();
        return;
    }
    HapticUtils.selectionClick();
    setState(() {
      _selectedPreset = preset;
      _selectedDateTime = next;
    });
  }

  Future<void> _pickDate() async {
    HapticUtils.selectionClick();
    final now = DateTime.now();
    final firstDate = DateTime(2000);
    final selectedDate = DateTime(
      _selectedDateTime.year,
      _selectedDateTime.month,
      _selectedDateTime.day,
    );
    final initialDate = selectedDate.isBefore(firstDate)
        ? firstDate
        : (selectedDate.isAfter(now) ? now : selectedDate);

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now,
      helpText: 'WHEN DID THIS HAPPEN?',
      cancelText: 'Cancel',
      confirmText: 'Choose date',
    );
    if (date == null || !mounted) return;

    final result = DateTime(
      date.year,
      date.month,
      date.day,
      _selectedDateTime.hour,
      _selectedDateTime.minute,
    );
    final safeResult = result.isAfter(DateTime.now()) ? DateTime.now() : result;

    setState(() {
      _selectedPreset = _isToday(safeResult)
          ? _WhenPreset.today
          : _WhenPreset.custom;
      _selectedDateTime = safeResult;
    });
  }

  Future<void> _pickTime() async {
    HapticUtils.selectionClick();
    final time = await showParkiWellTimePicker(
      context: context,
      selectedDate: _selectedDateTime,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _selectedDateTime = DateTime(
        _selectedDateTime.year,
        _selectedDateTime.month,
        _selectedDateTime.day,
        time.hour,
        time.minute,
      );
      _selectedPreset = _isToday(_selectedDateTime)
          ? _WhenPreset.today
          : _WhenPreset.custom;
    });
  }

  Future<void> _submitLog() async {
    final symptom = _symptomController.text.trim();
    if (symptom.isEmpty) {
      HapticUtils.error();
      _symptomFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe the symptom before saving.')),
      );
      return;
    }
    final selectedDateTime = _selectedPreset == _WhenPreset.now
        ? DateTime.now()
        : _selectedDateTime;
    if (selectedDateTime.isAfter(DateTime.now())) {
      HapticUtils.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A symptom cannot be logged in the future.'),
        ),
      );
      return;
    }

    HapticUtils.mediumImpact();
    setState(() => _isSaving = true);
    final saved = await singleton.saveLog(
      _formatStorageTime(selectedDateTime),
      symptom,
      _selectedSeverity,
    );
    if (!mounted) return;

    setState(() => _isSaving = false);
    if (!saved) {
      HapticUtils.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this symptom right now.')),
      );
      return;
    }

    HapticUtils.success();
    await Navigator.of(context).pushReplacementNamed('/logScreen');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TutorialOverlay(
      steps: const [],
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Log a symptom'),
        ),
        body: LiquidBackground(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    'Capture what changed',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'A short, specific note is easier to recognize later. You can backfill entries to any date from 2000 onward.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SectionHeading(title: 'What did you notice?'),
                  const SizedBox(height: 10),
                  GlassSurface(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      key: TutorialTargets.symptomInputKey,
                      child: TextField(
                        controller: _symptomController,
                        focusNode: _symptomFocus,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        minLines: 4,
                        maxLines: 6,
                        maxLength: 280,
                        decoration: const InputDecoration(
                          hintText:
                              'Example: Left-hand tremor became stronger after lunch…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          counterText: '',
                          contentPadding: EdgeInsets.fromLTRB(14, 13, 14, 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeading(
                    title: 'How noticeable was it?',
                    description: 'Choose the closest level for this moment.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _severityOptions
                        .map((severity) {
                          return _SeverityOption(
                            label: severity,
                            color: _severityColor(severity, colors),
                            selected: _selectedSeverity == severity,
                            onTap: () {
                              HapticUtils.selectionClick();
                              setState(() => _selectedSeverity = severity);
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeading(
                    title: 'When did it happen?',
                    description:
                        'Choose a day first, then adjust the time separately.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TimePresetChip(
                        label: 'Now',
                        selected: _selectedPreset == _WhenPreset.now,
                        onTap: () => _selectPreset(_WhenPreset.now),
                      ),
                      _TimePresetChip(
                        label: 'Today',
                        selected: _selectedPreset == _WhenPreset.today,
                        onTap: () => _selectPreset(_WhenPreset.today),
                      ),
                      _TimePresetChip(
                        label: 'Select date',
                        selected: _selectedPreset == _WhenPreset.custom,
                        onTap: () => _selectPreset(_WhenPreset.custom),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ParkiWellDateTimeField(
                          label: 'Date',
                          value: _formatDisplayDate(_selectedDateTime),
                          icon: Icons.calendar_today_outlined,
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ParkiWellDateTimeField(
                          label: 'Time',
                          value: _selectedPreset == _WhenPreset.now
                              ? 'Current time'
                              : _formatDisplayTime(_selectedDateTime),
                          icon: Icons.schedule_rounded,
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  if (_selectedPreset == _WhenPreset.now) ...[
                    const SizedBox(height: 8),
                    Text(
                      'The current time will be captured when you save.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.94),
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Container(
              key: TutorialTargets.saveSymptomButtonKey,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _symptomController,
                builder: (context, value, child) {
                  return FilledButton.icon(
                    onPressed: value.text.trim().isEmpty || _isSaving
                        ? null
                        : _submitLog,
                    icon: _isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textOnPrimary,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isSaving ? 'Saving…' : 'Save symptom'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeverityOption extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SeverityOption({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _AnimatedSelectionChip(
      label: label,
      selected: selected,
      accentColor: color,
      onTap: onTap,
    );
  }
}

class _TimePresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TimePresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _AnimatedSelectionChip(
      label: label,
      selected: selected,
      accentColor: context.colors.primary,
      onTap: onTap,
    );
  }
}

class _AnimatedSelectionChip extends StatefulWidget {
  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _AnimatedSelectionChip({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_AnimatedSelectionChip> createState() => _AnimatedSelectionChipState();
}

class _AnimatedSelectionChipState extends State<_AnimatedSelectionChip> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final pressDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 90);

    return Semantics(
      button: true,
      selected: widget.selected,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: pressDuration,
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: _setPressed,
            borderRadius: BorderRadius.circular(13),
            splashColor: widget.accentColor.withValues(alpha: 0.055),
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: selectionDuration,
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
              decoration: BoxDecoration(
                color: widget.selected
                    ? widget.accentColor.withValues(
                        alpha: context.isDarkMode ? 0.15 : 0.075,
                      )
                    : colors.cardBackground,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: widget.selected
                      ? widget.accentColor.withValues(alpha: 0.88)
                      : colors.border.withValues(alpha: 0.82),
                  width: widget.selected ? 1.4 : 1,
                ),
                boxShadow: widget.selected
                    ? [
                        BoxShadow(
                          color: widget.accentColor.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : const [],
              ),
              child: AnimatedDefaultTextStyle(
                duration: selectionDuration,
                curve: Curves.easeOutCubic,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: widget.selected
                      ? widget.accentColor
                      : colors.textSecondary,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
                child: Text(widget.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
