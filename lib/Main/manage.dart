import 'package:flutter/material.dart';

import '../singleton.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';

class ManageScreen extends StatefulWidget {
  final GlobalKey? logSymptomQuickActionKey;
  final GlobalKey? addMedicationQuickActionKey;
  final GlobalKey? medicationsToolCardKey;

  const ManageScreen({
    super.key,
    this.logSymptomQuickActionKey,
    this.addMedicationQuickActionKey,
    this.medicationsToolCardKey,
  });

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  final singleton = Singleton();

  int _medicationsDueToday() {
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final today = weekdays[DateTime.now().weekday - 1];
    var count = 0;
    for (final entry in singleton.schedule) {
      if (entry.length < 3) continue;
      final scheduleText = entry[2];
      if (scheduleText == 'Everyday' || scheduleText.contains(today)) {
        count += 1;
      }
    }
    return count;
  }

  int _currentLogStreak() {
    if (singleton.log.isEmpty) return 0;

    final dateKeys =
        singleton.log
            .map((entry) => entry.isNotEmpty ? _extractDateKey(entry[0]) : null)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();

    if (dateKeys.isEmpty) return 0;

    var cursor = DateTime.now();
    if (!dateKeys.contains(_toDateKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var streak = 0;
    while (dateKeys.contains(_toDateKey(cursor))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  String _extractDateKey(String value) {
    final parts = value.split(',');
    if (parts.length != 2) return _toDateKey(DateTime.now());
    final date = parts.last.trim().split(' ');
    if (date.length != 3) return _toDateKey(DateTime.now());

    const months = <String, int>{
      'January': 1,
      'February': 2,
      'March': 3,
      'April': 4,
      'May': 5,
      'June': 6,
      'July': 7,
      'August': 8,
      'September': 9,
      'October': 10,
      'November': 11,
      'December': 12,
    };

    final day = int.tryParse(date[0]);
    final month = months[date[1]];
    final year = int.tryParse(date[2]);
    if (day == null || month == null || year == null) {
      return _toDateKey(DateTime.now());
    }

    return _toDateKey(DateTime(year, month, day));
  }

  String _toDateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dueToday = _medicationsDueToday();
    final streak = _currentLogStreak();
    final totalLogs = singleton.log.length;
    final totalMeds = singleton.schedule.length;

    return LiquidBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  size: 17,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 7),
                Text(
                  'Your overview',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('manage-overview-strip'),
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.border.withValues(
                    alpha: context.isDarkMode ? 0.72 : 0.58,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(
                      alpha: context.isDarkMode ? 0.18 : 0.055,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _InsightMetric(
                        label: 'Symptom logs',
                        value: '$totalLogs',
                        icon: Icons.favorite_outline_rounded,
                        accentColor: colors.primary,
                      ),
                    ),
                    _MetricDivider(color: colors.divider),
                    Expanded(
                      child: _InsightMetric(
                        label: 'Meds today',
                        value: '$dueToday',
                        icon: Icons.medication_outlined,
                        accentColor: colors.secondary,
                      ),
                    ),
                    _MetricDivider(color: colors.divider),
                    Expanded(
                      child: _InsightMetric(
                        label: 'Streak',
                        value: '${streak}d',
                        icon: Icons.local_fire_department_outlined,
                        accentColor: colors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quick actions',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    cardKey: widget.logSymptomQuickActionKey,
                    icon: Icons.add_chart_rounded,
                    label: 'Log Symptom',
                    accentColor: colors.primary,
                    onTap: () {
                      HapticUtils.lightImpact();
                      Navigator.pushNamed(context, '/editLogScreen');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    cardKey: widget.addMedicationQuickActionKey,
                    icon: Icons.add_alarm_rounded,
                    label: 'Add Medication',
                    accentColor: colors.secondary,
                    onTap: () {
                      HapticUtils.lightImpact();
                      Navigator.pushNamed(context, '/editScheduleScreen');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Core tools',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ManageFeatureCard(
              icon: Icons.favorite_outline_rounded,
              title: 'Symptom Log',
              subtitle: 'Track and monitor your daily symptoms',
              statValue: '$totalLogs',
              statLabel: 'entries',
              onTap: () {
                HapticUtils.lightImpact();
                Navigator.pushNamed(context, '/logScreen');
              },
            ),
            const SizedBox(height: 12),
            _ManageFeatureCard(
              icon: Icons.medication_outlined,
              title: 'Medications',
              subtitle: 'Set reminders and track your medications',
              statValue: '$totalMeds',
              statLabel: 'scheduled',
              cardKey: widget.medicationsToolCardKey,
              onTap: () {
                HapticUtils.lightImpact();
                Navigator.pushNamed(context, '/scheduleScreen');
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;
  final GlobalKey? cardKey;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ModernCard(
      key: cardKey,
      onTap: onTap,
      backgroundColor: colors.cardBackground,
      border: Border.all(color: colors.border),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  const _InsightMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 18),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  final Color color;

  const _MetricDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: color.withValues(alpha: 0.72),
    );
  }
}

class _ManageFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String statValue;
  final String statLabel;
  final VoidCallback onTap;
  final GlobalKey? cardKey;

  const _ManageFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statValue,
    required this.statLabel,
    required this.onTap,
    this.cardKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ModernCard(
      key: cardKey,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$statValue $statLabel',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            color: colors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}
