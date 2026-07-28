import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A lightweight page backdrop that creates depth without animating or
/// blurring the entire screen. This keeps scrolling inexpensive while giving
/// primary screens a softer, more dimensional canvas.
class LiquidBackground extends StatelessWidget {
  final Widget child;

  const LiquidBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ColoredBox(
      color: colors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.08, -1.04),
                    radius: 1.05,
                    colors: [
                      colors.primary.withValues(
                        alpha: context.isDarkMode ? 0.16 : 0.10,
                      ),
                      colors.background.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.72],
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.15, 1.08),
                    radius: 0.92,
                    colors: [
                      colors.secondary.withValues(
                        alpha: context.isDarkMode ? 0.11 : 0.07,
                      ),
                      colors.background.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.76],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A restrained glass surface. Blur is opt-in and should be reserved for a
/// small number of fixed surfaces such as a bottom completion bar.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool blur;
  final Color? tint;
  final VoidCallback? onTap;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = false,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final surface = tint ?? colors.surface;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: context.isDarkMode ? 0.86 : 0.76),
        borderRadius: borderRadius,
        border: Border.all(
          color: context.isDarkMode
              ? colors.border.withValues(alpha: 0.78)
              : Colors.white.withValues(alpha: 0.88),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(
              alpha: context.isDarkMode ? 0.20 : 0.10,
            ),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: content,
            )
          : content,
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? trailing;

  const SectionHeading({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}
