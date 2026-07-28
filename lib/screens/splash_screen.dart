import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../widgets/parkiwell_mark.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _ambientController;
  late final AnimationController _exitController;

  late final Animation<double> _fadeIn;
  late final Animation<double> _brandLift;
  late final Animation<double> _logoScale;
  late final Animation<double> _progress;
  late final Animation<double> _exitFade;
  late final Animation<double> _exitScale;
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 1700),
      vsync: this,
    );

    _ambientController = AnimationController(
      duration: const Duration(milliseconds: 5600),
      vsync: this,
    );
    if (!_reduceMotion) {
      _ambientController.repeat();
    }

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeIn = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.05, 0.55, curve: Curves.easeOutBack),
      ),
    );

    _brandLift = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.2, 0.68, curve: Curves.easeOutCubic),
      ),
    );

    _progress = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.28, 1.0, curve: Curves.easeOutCubic),
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );

    _start();
  }

  Future<void> _start() async {
    if (_reduceMotion) {
      _entryController.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete();
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 120));
    await _entryController.forward();
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await _exitController.forward();
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _ambientController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );

    return Scaffold(
      body: FadeTransition(
        opacity: _exitFade,
        child: ScaleTransition(
          scale: _exitScale,
          child: AnimatedBuilder(
            animation: _ambientController,
            builder: (context, _) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        colors.background,
                        colors.primaryLight,
                        isDark ? 0.26 : 0.12,
                      )!,
                      Color.lerp(
                        colors.background,
                        colors.secondary,
                        isDark ? 0.18 : 0.06,
                      )!,
                      colors.background,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    _buildBackgroundGlow(
                      colors,
                      diameter: 260,
                      alignment: Alignment(
                        -0.85,
                        -0.92 +
                            (math.sin(_ambientController.value * 2 * math.pi) *
                                0.05),
                      ),
                      tint: colors.primary,
                    ),
                    _buildBackgroundGlow(
                      colors,
                      diameter: 340,
                      alignment: Alignment(
                        0.95,
                        -0.15 +
                            (math.cos(_ambientController.value * 2 * math.pi) *
                                0.04),
                      ),
                      tint: colors.secondary,
                    ),
                    _buildBackgroundGlow(
                      colors,
                      diameter: 300,
                      alignment: Alignment(
                        -0.3,
                        1.1 -
                            (math.sin(_ambientController.value * 2 * math.pi) *
                                0.03),
                      ),
                      tint: colors.primaryDark,
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Column(
                          children: [
                            const Spacer(flex: 3),
                            FadeTransition(
                              opacity: _fadeIn,
                              child: Transform.translate(
                                offset: Offset(0, _brandLift.value),
                                child: ScaleTransition(
                                  scale: _logoScale,
                                  child: _buildHeroLogo(colors, isDark: isDark),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FadeTransition(
                              opacity: _fadeIn,
                              child: Transform.translate(
                                offset: Offset(0, _brandLift.value),
                                child: Column(
                                  children: [
                                    Text(
                                      'ParkiWell',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 44,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -1.3,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Personalized Parkinson\'s care,\norganized every day.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 16,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(flex: 4),
                            FadeTransition(
                              opacity: _fadeIn,
                              child: _buildProgressSection(colors),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundGlow(
    AppColors colors, {
    required double diameter,
    required Alignment alignment,
    required Color tint,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                tint.withValues(alpha: 0.18),
                tint.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroLogo(AppColors colors, {required bool isDark}) {
    return ParkiWellMark(
      size: 128,
      color: isDark
          ? colors.textPrimary
          : colors.textPrimary.blend(colors.secondaryDark, 0.32),
    );
  }

  Widget _buildProgressSection(AppColors colors) {
    return Column(
      children: [
        Text(
          'Preparing your care workspace',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textTertiary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, child) {
              return LinearProgressIndicator(
                minHeight: 7,
                value: _progress.value,
                backgroundColor: colors.border.withValues(alpha: 0.42),
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              );
            },
          ),
        ),
      ],
    );
  }
}
