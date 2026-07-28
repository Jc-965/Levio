import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';

typedef RecoveryLogSave = Future<int> Function(DateTime completedAt);

Future<int?> showRecoveryLogSheet({
  required BuildContext context,
  required String title,
  required String typeLabel,
  required String duration,
  required IconData icon,
  required Color accent,
  required RecoveryLogSave onSave,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _RecoveryLogSheet(
      title: title,
      typeLabel: typeLabel,
      duration: duration,
      icon: icon,
      accent: accent,
      onSave: onSave,
    ),
  );
}

class _RecoveryLogSheet extends StatefulWidget {
  final String title;
  final String typeLabel;
  final String duration;
  final IconData icon;
  final Color accent;
  final RecoveryLogSave onSave;

  const _RecoveryLogSheet({
    required this.title,
    required this.typeLabel,
    required this.duration,
    required this.icon,
    required this.accent,
    required this.onSave,
  });

  @override
  State<_RecoveryLogSheet> createState() => _RecoveryLogSheetState();
}

class _RecoveryLogSheetState extends State<_RecoveryLogSheet> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _isSaving = false;
  String? _error;

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateUtils.dateOnly(now),
      helpText: 'When did you complete it?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    HapticUtils.mediumImpact();
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final completedAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        now.hour,
        now.minute,
      );
      final count = await widget.onSave(completedAt);
      if (count <= 0) throw StateError('Session could not be saved');
      if (!mounted) return;
      Navigator.pop(context, count);
    } catch (_) {
      if (!mounted) return;
      HapticUtils.error();
      setState(() {
        _isSaving = false;
        _error = 'This session could not be saved. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 18 + bottomInset),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Log completed session',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, color: widget.accent, size: 21),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.typeLabel}${widget.duration.isEmpty ? '' : ' · ${widget.duration}'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: 'Completion date ${formatRecoveryDate(_date)}',
              child: InkWell(
                onTap: _isSaving ? null : _chooseDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: colors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Completed',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: colors.textTertiary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatRecoveryDate(_date),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Change',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: colors.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.background,
                        ),
                      )
                    : const Text('Add to History'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatRecoveryDate(DateTime date) {
  final today = DateUtils.dateOnly(DateTime.now());
  final selected = DateUtils.dateOnly(date);
  if (selected == today) return 'Today';
  if (selected == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const months = [
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
