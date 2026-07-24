import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';
import 'motion_analysis.dart';

enum MotionCoachResultAction { useRecording, retry }

class MotionCoachResultsScreen extends StatelessWidget {
  const MotionCoachResultsScreen({super.key, required this.result});

  final MotionAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bool setupHelp = result.needsSetupHelp;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Motion check'),
      ),
      body: LiquidBackground(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ModernCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(20),
                  backgroundColor: setupHelp
                      ? colors.warning.withValues(alpha: 0.11)
                      : colors.success.withValues(alpha: 0.11),
                  border: Border.all(
                    color: (setupHelp ? colors.warning : colors.success)
                        .withValues(alpha: 0.32),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: (setupHelp ? colors.warning : colors.success)
                              .withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          setupHelp ? Icons.tune_rounded : Icons.check_rounded,
                          color: setupHelp ? colors.warning : colors.success,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        setupHelp
                            ? 'Let’s adjust the setup'
                            : 'Movement captured',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        setupHelp
                            ? _setupMessage(result)
                            : 'Here are neutral camera observations from this practice.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (!setupHelp) ...[
                  _EvidenceReportCard(result: result),
                  const SizedBox(height: 14),
                  _ObservationCard(
                    icon: Icons.repeat_rounded,
                    title: 'Complete raises',
                    value: '${result.repCount}',
                    detail: 'Both arms moved through a complete cycle.',
                  ),
                  const SizedBox(height: 10),
                  if (result.rangeDegrees != null)
                    _ObservationCard(
                      icon: Icons.expand_rounded,
                      title: 'Observed arm range',
                      value: '${result.rangeDegrees!.round()}°',
                      detail:
                          'Median change in arm elevation during complete raises'
                          '${result.rangePercentOfReference == null ? '.' : ' — '
                                    '${result.rangePercentOfReference!.round()}% of '
                                    'this exercise reference.'}',
                    ),
                  if (result.rangeDegrees != null) const SizedBox(height: 10),
                  if (result.tempoSeconds != null)
                    _ObservationCard(
                      icon: Icons.timer_outlined,
                      title: 'Observed pace',
                      value: '${result.tempoSeconds!.toStringAsFixed(1)} sec',
                      detail: 'Median duration of one complete raise.',
                    ),
                  if (result.tempoSeconds != null) const SizedBox(height: 10),
                  if (result.sideRangeRatio != null)
                    _ObservationCard(
                      icon: Icons.compare_arrows_rounded,
                      title: 'Side-to-side range ratio',
                      value: '${(result.sideRangeRatio! * 100).round()}%',
                      detail:
                          'Smaller observed arm range divided by the larger range.',
                    ),
                  if (result.sequenceSummary != null) ...[
                    const SizedBox(height: 10),
                    _ObservationCard(
                      icon: Icons.trending_flat_rounded,
                      title: 'First-to-last range',
                      value:
                          '${result.repetitions.first.romDegrees.round()}° → '
                          '${result.repetitions.last.romDegrees.round()}°',
                      detail:
                          '${(result.amplitudeSequenceLastFirstRatio! * 100).round()}% '
                          'last-to-first. This is a camera observation, not a '
                          'fatigue score.',
                    ),
                  ],
                  const SizedBox(height: 14),
                ],
                ModernCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: colors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your video and pose landmarks stay on this device. '
                          'These observations are not a diagnosis or a medical '
                          'assessment.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(MotionCoachResultAction.useRecording),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      setupHelp ? 'Keep private recording' : 'Use this result',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(MotionCoachResultAction.retry),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceReportCard extends StatelessWidget {
  const _EvidenceReportCard({required this.result});

  final MotionAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notes_rounded, color: colors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Practice summary',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.evidenceSummary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          if (result.sequenceSummary case final String sequence) ...[
            const SizedBox(height: 10),
            Text(
              sequence,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            result.measurementLimits,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textTertiary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

String _setupMessage(MotionAnalysisResult result) {
  final Set<String> reasons = <String>{...result.reasonCodes, ...result.flags};
  if (reasons.contains('low_sampling_rate')) {
    return 'This device did not analyze frames quickly enough for a reliable '
        'summary. Good lighting may help, or keep the recording for a private '
        'self-review.';
  }
  if (reasons.contains('pose_discontinuity')) {
    return 'Keep one person in view and hold the phone steady, then try again.';
  }
  if (reasons.contains('bilateral_movement_required')) {
    return 'Move both arms out to the sides together, then return them to a '
        'comfortable resting position.';
  }
  if (reasons.contains('no_complete_reps')) {
    return 'No complete arm raises were detected. Begin with both arms at rest, '
        'raise them comfortably, then return to rest.';
  }
  return 'Keep your face, shoulders, wrists, and hips visible in steady light, '
      'then try the movement again.';
}

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: colors.secondary, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
