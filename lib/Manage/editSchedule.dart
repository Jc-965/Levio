import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../singleton.dart';
import '../services/tutorial_targets.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/modern_card.dart';
import '../widgets/modern_input.dart';
import '../widgets/tutorial_overlay.dart';

class EditScheduleScreen extends StatefulWidget {
  const EditScheduleScreen({super.key});

  @override
  State<EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<EditScheduleScreen>
    with SingleTickerProviderStateMixin {
  final singleton = Singleton();
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();

  static const List<String> _daysOfWeek = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  late final AnimationController _animationController;
  late final Animation<double> _animation;

  List<String> selectedDays = <String>[];
  final List<TimeOfDay> _doseTimes = <TimeOfDay>[];
  bool _isLoading = false;

  String _formatDoseTimes() {
    final sorted = List<TimeOfDay>.from(_doseTimes)
      ..sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
    return sorted
        .map(
          (t) =>
              '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}',
        )
        .join(',');
  }

  Future<void> _addDoseTime() async {
    HapticUtils.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Dose time',
    );
    if (picked == null || !mounted) return;
    if (_doseTimes.any(
      (t) => t.hour == picked.hour && t.minute == picked.minute,
    )) {
      return;
    }
    setState(() => _doseTimes.add(picked));
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    )..forward();
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _toggleDay(String day) {
    HapticUtils.selectionClick();
    setState(() {
      if (selectedDays.contains(day)) {
        selectedDays.remove(day);
      } else {
        selectedDays.add(day);
      }
    });
  }

  void _applyTemplate(String template) {
    HapticUtils.lightImpact();
    setState(() {
      if (template == 'Everyday') {
        selectedDays = List<String>.from(_daysOfWeek);
      } else if (template == 'Weekdays') {
        selectedDays = _daysOfWeek.sublist(0, 5);
      } else {
        selectedDays = <String>['Saturday', 'Sunday'];
      }
    });
  }

  bool _templateSelected(String template) {
    final selected = selectedDays.toSet();

    if (template == 'Everyday') {
      return selected.length == _daysOfWeek.length;
    }

    if (template == 'Weekdays') {
      final weekdays = _daysOfWeek.sublist(0, 5).toSet();
      return selected.length == weekdays.length &&
          selected.containsAll(weekdays);
    }

    final weekends = <String>{'Saturday', 'Sunday'};
    return selected.length == weekends.length && selected.containsAll(weekends);
  }

  String _formatSchedule() {
    if (selectedDays.isEmpty) return 'No days selected';
    if (selectedDays.length == _daysOfWeek.length) return 'Everyday';
    return 'Every ${selectedDays.join(', ')}';
  }

  Future<void> _submitSchedule() async {
    if (_nameController.text.trim().isEmpty) {
      HapticUtils.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter medication name'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }

    if (selectedDays.isEmpty) {
      HapticUtils.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one day'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticUtils.mediumImpact();

    try {
      final saved = await singleton.saveSchedule(
        _nameController.text.trim(),
        _detailsController.text.trim(),
        _formatSchedule(),
        doseTimes: _formatDoseTimes(),
      );

      if (!saved) {
        throw Exception('Unable to save medication schedule');
      }

      HapticUtils.success();
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      HapticUtils.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving medication: $e'),
          backgroundColor: context.colors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessDialog() {
    final colors = context.colors;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext c) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: colors.success,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text('Medication Saved', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Your medication schedule is now active.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  c,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        _nameController.clear();
                        _detailsController.clear();
                        setState(() => selectedDays.clear());
                      },
                      child: const Text('Add More'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(c);
                        // Replace so the back stack does not grow on each
                        // save-and-view round trip.
                        Navigator.pushReplacementNamed(
                          context,
                          '/scheduleScreen',
                        );
                      },
                      child: const Text('View Meds'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTemplateSelector() {
    const templates = <String>['Everyday', 'Weekdays', 'Weekends'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: templates.map((template) {
        return _SelectionChip(
          label: template,
          selected: _templateSelected(template),
          onTap: () => _applyTemplate(template),
        );
      }).toList(),
    );
  }

  Widget _buildDaySelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _daysOfWeek.map((day) {
        return _SelectionChip(
          label: day.substring(0, 3),
          selected: selectedDays.contains(day),
          onTap: () => _toggleDay(day),
          compact: true,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
            icon: Icon(
              Icons.arrow_back_rounded,
              color: colors.textPrimary,
              size: 22,
            ),
            onPressed: () {
              HapticUtils.lightImpact();
              Navigator.popAndPushNamed(context, '/scheduleScreen');
            },
          ),
          title: Text(
            'Medication Log',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: FadeTransition(
          opacity: _animation,
          child: Container(
            color: colors.background,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create medication schedule',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add medication details and assign the days to take it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ModernCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Medication Name',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          key: TutorialTargets.medicationNameInputKey,
                          child: ModernTextField(
                            controller: _nameController,
                            hint: 'e.g., Levodopa 100mg',
                            // Stay under the 200-char server cap for
                            // medication_events.medication_name; exceeding
                            // it would poison the sync journal.
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(120),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Details (optional)',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ModernTextField(
                          controller: _detailsController,
                          hint: 'Dosage notes or instructions',
                          maxLines: 2,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(500),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: colors.border, height: 1),
                        const SizedBox(height: 12),
                        Text(
                          'Quick templates',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _buildTemplateSelector(),
                        const SizedBox(height: 14),
                        Text(
                          'Select days',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _buildDaySelector(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.border, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          color: colors.textPrimary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _formatSchedule(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Dose times (optional)',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final time in _doseTimes)
                        InputChip(
                          label: Text(time.format(context)),
                          onDeleted: () {
                            HapticUtils.selectionClick();
                            setState(() => _doseTimes.remove(time));
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_alarm_rounded, size: 18),
                        label: const Text('Add time'),
                        onPressed: _addDoseTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _doseTimes.isEmpty
                        ? 'Without dose times, reminders use the time set in '
                              'Settings.'
                        : 'Reminders fire at each dose time on the selected '
                              'days.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      key: TutorialTargets.saveMedicationButtonKey,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _submitSchedule,
                        icon: _isLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colors.textOnPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _isLoading ? 'Saving...' : 'Save Medication',
                        ),
                      ),
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

class _SelectionChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  const _SelectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_SelectionChip> createState() => _SelectionChipState();
}

class _SelectionChipState extends State<_SelectionChip> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 12 : 14,
          vertical: widget.compact ? 8 : 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? colors.primary : colors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
