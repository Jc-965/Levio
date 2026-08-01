import 'package:flutter/material.dart';

import '../singleton.dart';
import '../services/tutorial_targets.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/modern_button.dart';
import '../widgets/modern_card.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final singleton = Singleton();

  String name(int index) => singleton.schedule[index][0];
  String detail(int index) => singleton.schedule[index][1];
  String schedule(int index) => singleton.schedule[index][2];

  Color _scheduleColor(String value, AppColors colors) {
    final text = value.toLowerCase();
    if (text.contains('everyday')) return colors.success;
    if (text.contains('weekend')) return colors.warning;
    if (text.contains('monday') || text.contains('tuesday')) {
      return colors.secondary;
    }
    return colors.info;
  }

  void _showMedicationDetails(int index) {
    final colors = context.colors;
    HapticUtils.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext c) {
        final scheduleColor = _scheduleColor(schedule(index), colors);

        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ModernCard(
                  backgroundColor: colors.surfaceVariant,
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.9),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.medication_rounded, color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name(index).isEmpty ? 'Medication' : name(index),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _DetailRow(
                  label: 'Medication',
                  value: name(index),
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Details',
                  value: detail(index),
                  colors: colors,
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Schedule',
                  value: schedule(index),
                  colors: colors,
                  badgeColor: scheduleColor,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ModernButton(
                    text: 'Mark as Taken',
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: () async {
                      HapticUtils.success();
                      final saved = await singleton.recordMedicationTaken(
                        index,
                      );
                      if (!mounted || !c.mounted) return;
                      Navigator.pop(c);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            saved
                                ? '${name(index)} recorded'
                                : 'Unable to record this dose',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ModernButton(
                        text: 'Close',
                        isOutlined: true,
                        onPressed: () => Navigator.pop(c),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ModernIconButton(
                      icon: Icons.edit_outlined,
                      backgroundColor: colors.secondary,
                      onPressed: () async {
                        Navigator.pop(c);
                        await _showEditMedicationDialog(index);
                      },
                    ),
                    const SizedBox(width: 10),
                    ModernIconButton(
                      icon: Icons.delete_outline_rounded,
                      backgroundColor: colors.error,
                      onPressed: () async {
                        HapticUtils.lightImpact();
                        // Confirm first: a tremor tap must never silently
                        // delete a medication schedule.
                        final confirmed = await showDialog<bool>(
                          context: c,
                          builder: (dc) => AlertDialog(
                            title: const Text('Delete Medication'),
                            content: const Text(
                              'Delete this medication schedule? This cannot '
                              'be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dc, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(dc, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await singleton.deleteEntireList(index, 'schedules');
                        if (!mounted || !c.mounted) return;
                        Navigator.pop(c);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditMedicationDialog(int index) async {
    if (index < 0 || index >= singleton.schedule.length) return;
    final colors = context.colors;
    final nameController = TextEditingController(text: name(index));
    final detailsController = TextEditingController(text: detail(index));
    final daysController = TextEditingController(text: schedule(index));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext c) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Medication',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Medication Name',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(labelText: 'Details'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: daysController,
                  decoration: const InputDecoration(labelText: 'Schedule'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ModernButton(
                        text: 'Cancel',
                        isOutlined: true,
                        onPressed: () => Navigator.pop(c),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ModernButton(
                        text: 'Save',
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) return;
                          await singleton.updateScheduleEntry(
                            index,
                            nameController.text.trim(),
                            detailsController.text.trim(),
                            daysController.text.trim(),
                            // Editing name/details must not drop the
                            // medication's per-dose reminder times.
                            doseTimes: singleton.schedule[index].length > 3
                                ? singleton.schedule[index][3]
                                : '',
                          );
                          if (!mounted || !c.mounted) return;
                          Navigator.pop(c);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    nameController.dispose();
    detailsController.dispose();
    daysController.dispose();
  }

  Widget _buildSummary(AppColors colors) {
    final total = singleton.schedule.length;
    final daily = singleton.schedule
        .where(
          (entry) =>
              entry.length > 2 && entry[2].toLowerCase().contains('everyday'),
        )
        .length;

    return ModernCard(
      backgroundColor: colors.cardBackground,
      border: Border.all(color: colors.border),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Medication overview',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$total active medications',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            '$daily daily schedules',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () {
            HapticUtils.lightImpact();
            // Pop back instead of pushing a duplicate app shell.
            Navigator.of(context).maybePop();
          },
        ),
        title: Text(
          'Medications',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Container(
        color: colors.background,
        child: singleton.schedule.isEmpty
            ? _buildEmptyState(colors)
            : _buildScheduleList(colors),
      ),
      floatingActionButton: Container(
        key: TutorialTargets.scheduleAddMedicationKey,
        child: ModernFAB(
          icon: Icons.add,
          backgroundColor: colors.primaryDark,
          onPressed: () =>
              Navigator.popAndPushNamed(context, '/editScheduleScreen'),
          extended: true,
          label: 'Add Medication',
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: ModernCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.medication_liquid_outlined,
                color: colors.secondary,
                size: 38,
              ),
              const SizedBox(height: 16),
              Text(
                'No medications added',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Create medication schedules to stay on track with treatments.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ModernButton(
                  text: 'Add First Medication',
                  icon: Icons.add_rounded,
                  onPressed: () =>
                      Navigator.popAndPushNamed(context, '/editScheduleScreen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleList(AppColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 90),
      itemCount: singleton.schedule.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSummary(colors),
          );
        }

        final row = index - 1;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ScheduleCard(
            name: name(row),
            detail: detail(row),
            schedule: schedule(row),
            onTap: () => _showMedicationDetails(row),
          ),
        );
      },
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final String name;
  final String detail;
  final String schedule;
  final VoidCallback onTap;

  const _ScheduleCard({
    required this.name,
    required this.detail,
    required this.schedule,
    required this.onTap,
  });

  Color _scheduleColor(String value, AppColors colors) {
    final text = value.toLowerCase();
    if (text.contains('everyday')) return colors.success;
    if (text.contains('weekend')) return colors.warning;
    if (text.contains('monday') || text.contains('tuesday')) {
      return colors.secondary;
    }
    return colors.info;
  }

  String _compactScheduleLabel(String value) {
    final text = value.trim();
    if (text.toLowerCase().contains('everyday')) return 'Everyday';
    if (text.length <= 18) return text;
    if (text.startsWith('Every ')) {
      final days = text.substring(6).split(',');
      if (days.length > 1) {
        return '${days.first.trim()} +${days.length - 1}';
      }
    }
    return '${text.substring(0, 15)}...';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheduleColor = _scheduleColor(schedule, colors);
    final compactSchedule = _compactScheduleLabel(schedule);

    return ModernCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.medication_outlined, color: colors.secondary, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Medication' : name,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  detail.isEmpty ? schedule : detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheduleColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              compactSchedule,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheduleColor,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final AppColors colors;
  final Color? badgeColor;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.colors,
    this.badgeColor,
  });

  String _compactBadgeText(String text) {
    final value = text.trim();
    if (value.isEmpty) return '';
    if (value.toLowerCase().contains('everyday')) return 'Everyday';
    if (value.startsWith('Every ')) {
      final days = value.substring(6).split(',');
      if (days.length > 1) {
        return '${days.first.trim()} +${days.length - 1}';
      }
    }
    if (value.length <= 22) return value;
    return '${value.substring(0, 19)}...';
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? 'Not specified' : value;
    final badgeText = _compactBadgeText(displayValue);

    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(displayValue, style: Theme.of(context).textTheme.bodyMedium),
          if (badgeColor != null && badgeText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor!.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
