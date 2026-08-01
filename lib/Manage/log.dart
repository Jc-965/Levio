import 'package:flutter/material.dart';

import '../singleton.dart';
import '../utils/log_timestamp.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/date_time_controls.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  static const List<String> _severityOptions = <String>[
    'Very Mild',
    'Mild',
    'Moderate',
    'Severe',
    'Very Severe',
  ];
  static const List<String> _monthNames = <String>[
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

  String _time(int index) => singleton.log[index][0];
  String _symptom(int index) => singleton.log[index][1];
  String _severity(int index) => singleton.log[index][2];

  DateTime? _parseStorageTime(String value) => parseLogTimestamp(value);

  String _formatStorageTime(DateTime value) => formatLogTimestamp(value);

  String _formatTime(DateTime? value) {
    if (value == null) return 'Time unavailable';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _formatFullDateTime(DateTime? value) {
    if (value == null) return 'Date unavailable';
    return '${_monthNames[value.month - 1]} ${value.day}, ${value.year} at ${_formatTime(value)}';
  }

  String _groupLabel(DateTime? value) {
    if (value == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_monthNames[value.month - 1]} ${value.day}, ${value.year}';
  }

  bool _startsNewGroup(int index) {
    if (index == 0) return true;
    final current = _parseStorageTime(_time(index));
    final previous = _parseStorageTime(_time(index - 1));
    if (current == null || previous == null) return true;
    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  Color _severityColor(String value, AppColors colors) {
    final text = value.toLowerCase();
    if (text.contains('mild')) return colors.success;
    if (text.contains('moderate')) return colors.warning;
    if (text.contains('severe')) return colors.error;
    return colors.info;
  }

  Future<void> _showLogDetails(int index) async {
    HapticUtils.lightImpact();
    final colors = context.colors;
    final date = _parseStorageTime(_time(index));
    final severityColor = _severityColor(_severity(index), colors);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: colors.border)),
          ),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Symptom details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _severity(index),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: severityColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatFullDateTime(date),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              Text(
                _symptom(index),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _showEditLogSheet(index);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        // Confirm first: a tremor tap must never destroy a
                        // medical record irreversibly.
                        final confirmed = await showDialog<bool>(
                          context: sheetContext,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete Log Entry'),
                            content: const Text(
                              'Delete this symptom log entry? This cannot '
                              'be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await singleton.deleteLog(index);
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Symptom log deleted.')),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditLogSheet(int index) async {
    if (index < 0 || index >= singleton.log.length) return;
    final colors = context.colors;
    final symptomController = TextEditingController(text: _symptom(index));
    var selectedSeverity = _severity(index);
    var selectedDateTime = _parseStorageTime(_time(index)) ?? DateTime.now();
    var isSaving = false;

    Future<void> pickDate(StateSetter setSheetState) async {
      final now = DateTime.now();
      final firstDate = DateTime(2000);
      final initial = selectedDateTime.isBefore(firstDate)
          ? firstDate
          : (selectedDateTime.isAfter(now) ? now : selectedDateTime);
      final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: firstDate,
        lastDate: now,
        helpText: 'WHEN DID THIS HAPPEN?',
      );
      if (date == null || !mounted) return;

      final result = DateTime(
        date.year,
        date.month,
        date.day,
        selectedDateTime.hour,
        selectedDateTime.minute,
      );
      setSheetState(() {
        selectedDateTime = result.isAfter(now) ? now : result;
      });
    }

    Future<void> pickTime(StateSetter setSheetState) async {
      final time = await showParkiWellTimePicker(
        context: context,
        selectedDate: selectedDateTime,
        initialTime: TimeOfDay.fromDateTime(selectedDateTime),
      );
      if (time == null || !mounted) return;
      setSheetState(() {
        selectedDateTime = DateTime(
          selectedDateTime.year,
          selectedDateTime.month,
          selectedDateTime.day,
          time.hour,
          time.minute,
        );
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 24),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: SingleChildScrollView(
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
                  const SizedBox(height: 18),
                  Text(
                    'Edit symptom',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: symptomController,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 280,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What did you notice?',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSeverity,
                    decoration: const InputDecoration(labelText: 'Severity'),
                    items: _severityOptions
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => selectedSeverity = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ParkiWellDateTimeField(
                          label: 'Date',
                          value:
                              '${_monthNames[selectedDateTime.month - 1]} ${selectedDateTime.day}, ${selectedDateTime.year}',
                          icon: Icons.calendar_today_outlined,
                          onTap: () => pickDate(setSheetState),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ParkiWellDateTimeField(
                          label: 'Time',
                          value: _formatTime(selectedDateTime),
                          icon: Icons.schedule_rounded,
                          onTap: () => pickTime(setSheetState),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (symptomController.text.trim().isEmpty) return;
                              setSheetState(() => isSaving = true);
                              final saved = await singleton.updateLogEntry(
                                index,
                                _formatStorageTime(selectedDateTime),
                                symptomController.text.trim(),
                                selectedSeverity,
                              );
                              if (!mounted || !sheetContext.mounted) return;
                              if (saved) {
                                Navigator.pop(sheetContext);
                                setState(() {});
                              } else {
                                setSheetState(() => isSaving = false);
                              }
                            },
                      icon: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(isSaving ? 'Saving…' : 'Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    symptomController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            HapticUtils.lightImpact();
            Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Symptom history'),
      ),
      body: LiquidBackground(
        child: singleton.log.isEmpty
            ? _buildEmptyState(colors)
            : _buildLogList(colors),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).pushReplacementNamed('/editLogScreen'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log symptom'),
      ),
    );
  }

  Widget _buildEmptyState(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_heart_outlined, color: colors.primary, size: 42),
            const SizedBox(height: 18),
            Text(
              'Your history starts here',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'Log a symptom from today or add an older entry so changes are easier to recognize over time.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed('/editLogScreen'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Log your first symptom'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(AppColors colors) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 104),
      itemCount: singleton.log.length + 1,
      itemBuilder: (context, listIndex) {
        if (listIndex == 0) {
          final latest = _parseStorageTime(_time(0));
          return Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: GlassSurface(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${singleton.log.length}',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          singleton.log.length == 1
                              ? 'symptom recorded'
                              : 'symptoms recorded',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Latest\n${_groupLabel(latest)}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final index = listIndex - 1;
        final date = _parseStorageTime(_time(index));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_startsNewGroup(index)) ...[
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 9, top: 2),
                child: Text(
                  _groupLabel(date),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LogCard(
                time: _formatTime(date),
                symptom: _symptom(index),
                severity: _severity(index),
                onTap: () => _showLogDetails(index),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LogCard extends StatelessWidget {
  final String time;
  final String symptom;
  final String severity;
  final VoidCallback onTap;

  const _LogCard({
    required this.time,
    required this.symptom,
    required this.severity,
    required this.onTap,
  });

  Color _severityColor(String value, AppColors colors) {
    final text = value.toLowerCase();
    if (text.contains('mild')) return colors.success;
    if (text.contains('moderate')) return colors.warning;
    if (text.contains('severe')) return colors.error;
    return colors.info;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final severityColor = _severityColor(severity, colors);
    return ModernCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 42,
            decoration: BoxDecoration(
              color: severityColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symptom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$time · $severity',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: colors.textTertiary,
            size: 20,
          ),
        ],
      ),
    );
  }
}
