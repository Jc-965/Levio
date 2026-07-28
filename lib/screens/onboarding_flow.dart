import 'package:flutter/material.dart';

import '../Main/editProfile.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/parkiwell_mark.dart';
import '../widgets/stage_transition_switcher.dart';

class OnboardingFlowScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingFlowScreen({super.key, required this.onComplete});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen>
    with SingleTickerProviderStateMixin {
  bool _showAccountFlow = false;
  bool _startInSignIn = false;
  bool _returningToWelcome = false;
  late final AnimationController _introController;

  static const List<_OnboardingBenefit> _benefits = <_OnboardingBenefit>[
    _OnboardingBenefit(
      icon: Icons.monitor_heart_outlined,
      title: 'See your day clearly',
      description: 'Keep symptoms and medication routines together.',
    ),
    _OnboardingBenefit(
      icon: Icons.self_improvement_outlined,
      title: 'Build a recovery rhythm',
      description: 'Set approachable speech and movement goals.',
    ),
    _OnboardingBenefit(
      icon: Icons.insights_outlined,
      title: 'Notice patterns over time',
      description: 'Review progress without losing access when offline.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _introController.value = 1;
      } else {
        _introController.forward();
      }
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  Widget _reveal({required int order, required Widget child}) {
    final start = (order * 0.11).clamp(0.0, 0.55);
    final curved = CurvedAnimation(
      parent: _introController,
      curve: Interval(
        start,
        (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  void _openAccountFlow({required bool signIn}) {
    if (signIn) {
      HapticUtils.lightImpact();
    } else {
      HapticUtils.selectionClick();
    }
    setState(() {
      _startInSignIn = signIn;
      _showAccountFlow = true;
      _returningToWelcome = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stage = _showAccountFlow
        ? EditProfileScreen(
            key: ValueKey<String>(
              _startInSignIn ? 'sign-in-stage' : 'sign-up-stage',
            ),
            onComplete: widget.onComplete,
            startInSignIn: _startInSignIn,
            onBack: () => setState(() {
              _showAccountFlow = false;
              _returningToWelcome = true;
            }),
          )
        : KeyedSubtree(
            key: const ValueKey<String>('welcome-stage'),
            child: _buildWelcome(context),
          );

    return DecoratedBox(
      decoration: _backdropDecoration(context),
      child: StageTransitionSwitcher(
        reverse: _returningToWelcome,
        child: stage,
      ),
    );
  }

  BoxDecoration _backdropDecoration(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: colors.background,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          colors.background.blend(colors.primaryLight, isDark ? 0.18 : 0.1),
          colors.background.blend(colors.secondaryLight, isDark ? 0.12 : 0.05),
          colors.background,
        ],
        stops: const <double>[0, 0.46, 1],
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      body: Container(
        decoration: _backdropDecoration(context),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -96,
              right: -88,
              child: _AmbientShape(
                size: 240,
                color: colors.primary.withValues(alpha: isDark ? 0.11 : 0.07),
              ),
            ),
            Positioned(
              bottom: 110,
              left: -110,
              child: _AmbientShape(
                size: 260,
                color: colors.secondary.withValues(alpha: isDark ? 0.1 : 0.06),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(
                    context,
                  ).scale(1).clamp(1.0, 2.0);
                  final compact =
                      constraints.maxHeight < 730 || textScale > 1.15;

                  return Column(
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compact ? 10 : 16,
                          24,
                          0,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: _reveal(
                              order: 0,
                              child: _buildBrandRow(colors, compact: compact),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            compact ? 8 : 14,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  _reveal(
                                    order: 1,
                                    child: Semantics(
                                      header: true,
                                      child: Text(
                                        'A calmer way to manage Parkinson\'s care',
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            (compact
                                                    ? Theme.of(
                                                        context,
                                                      ).textTheme.headlineSmall
                                                    : Theme.of(context)
                                                          .textTheme
                                                          .headlineMedium)
                                                ?.copyWith(
                                                  color: colors.textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.1,
                                                  letterSpacing: compact
                                                      ? -0.45
                                                      : -0.7,
                                                ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: compact ? 7 : 10),
                                  _reveal(
                                    order: 2,
                                    child: Text(
                                      'Organize daily care, follow guided recovery, and understand your progress in one supportive place.',
                                      textAlign: TextAlign.center,
                                      maxLines: compact ? 3 : 4,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          (compact
                                                  ? Theme.of(
                                                      context,
                                                    ).textTheme.bodyMedium
                                                  : Theme.of(
                                                      context,
                                                    ).textTheme.bodyLarge)
                                              ?.copyWith(
                                                color: colors.textSecondary,
                                                height: compact ? 1.35 : 1.42,
                                                fontWeight: FontWeight.w500,
                                              ),
                                    ),
                                  ),
                                  SizedBox(height: compact ? 13 : 20),
                                  _reveal(
                                    order: 3,
                                    child: _buildBenefitsCard(
                                      colors,
                                      compact: compact,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildActionArea(colors, compact: compact),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandRow(AppColors colors, {required bool compact}) {
    return Row(
      children: <Widget>[
        ParkiWellMark(
          size: compact ? 38 : 42,
          color: colors.textPrimary.blend(colors.secondary, 0.28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ParkiWell',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Your everyday care companion',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitsCard(AppColors colors, {required bool compact}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.shadow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: List<Widget>.generate(_benefits.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 1,
              indent: 74,
              endIndent: 20,
              color: colors.divider,
            );
          }

          final benefit = _benefits[index ~/ 2];
          final accent = index == 0
              ? colors.primary
              : index == 2
              ? colors.secondary
              : colors.primaryDark;
          return _BenefitRow(
            benefit: benefit,
            colors: colors,
            accent: accent,
            compact: compact,
          );
        }),
      ),
    );
  }

  Widget _buildActionArea(AppColors colors, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, compact ? 8 : 11, 24, compact ? 10 : 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _reveal(
                order: 4,
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => _openAccountFlow(signIn: false),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: const Text('Create my care plan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primaryDark.blend(
                        colors.primary,
                        0.18,
                      ),
                      foregroundColor: colors.textOnPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _reveal(
                order: 5,
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _openAccountFlow(signIn: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      backgroundColor: colors.surface,
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('I already have an account'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingBenefit {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingBenefit({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _BenefitRow extends StatelessWidget {
  final _OnboardingBenefit benefit;
  final AppColors colors;
  final Color accent;
  final bool compact;

  const _BenefitRow({
    required this.benefit,
    required this.colors,
    required this.accent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 11 : 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(benefit.icon, size: compact ? 20 : 22, color: accent),
          SizedBox(width: compact ? 11 : 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  benefit.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    benefit.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.34,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientShape extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientShape({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.34),
        ),
      ),
    );
  }
}
