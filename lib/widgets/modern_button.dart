import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';

class ModernButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final EdgeInsets? padding;

  const ModernButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.padding,
  });

  @override
  State<ModernButton> createState() => _ModernButtonState();
}

class _ModernButtonState extends State<ModernButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (!widget.isLoading) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = widget.backgroundColor ?? colors.primary;
    final textColor = widget.textColor ?? colors.textOnPrimary;
    final pressedBackground = backgroundColor.blend(colors.primaryDark, 0.08);

    final gradient = widget.isOutlined
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Blend toward the darker primary so the gradient's light end
            // never dips below AA contrast with the button label.
            colors: [
              backgroundColor,
              backgroundColor.blend(colors.primaryDark, 0.25),
            ],
          );

    return Semantics(
      button: true,
      enabled: !widget.isLoading,
      label: widget.text,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.isLoading
            ? null
            : () {
                HapticUtils.lightImpact();
                widget.onPressed();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.width,
          constraints: const BoxConstraints(minHeight: 48),
          padding:
              widget.padding ??
              const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          transform: Matrix4.identity()
            ..scaleByDouble(
              _isPressed ? 0.985 : 1.0,
              _isPressed ? 0.985 : 1.0,
              1.0,
              1.0,
            ),
          decoration: BoxDecoration(
            color: widget.isOutlined
                ? (_isPressed
                      ? colors.surface.blend(colors.primary, 0.08)
                      : colors.surfaceVariant)
                : null,
            gradient: widget.isOutlined
                ? null
                : (_isPressed
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            pressedBackground,
                            pressedBackground.blend(colors.primaryLight, 0.18),
                          ],
                        )
                      : gradient),
            borderRadius: BorderRadius.circular(14),
            border: widget.isOutlined
                ? Border.all(
                    color: colors.border.blend(colors.primary, 0.12),
                    width: 1,
                  )
                : null,
            boxShadow: widget.isOutlined
                ? null
                : [
                    BoxShadow(
                      color: colors.shadow.blend(backgroundColor, 0.18),
                      blurRadius: _isPressed ? 8 : 16,
                      offset: Offset(0, _isPressed ? 4 : 8),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      widget.isOutlined ? colors.textSecondary : textColor,
                    ),
                  ),
                )
              else ...[
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    color: widget.isOutlined ? colors.textPrimary : textColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.text,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: widget.isOutlined ? colors.textPrimary : textColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ModernIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final bool isCircle;
  final String? semanticLabel;

  const ModernIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 48,
    this.isCircle = false,
    this.semanticLabel,
  });

  @override
  State<ModernIconButton> createState() => _ModernIconButtonState();
}

class _ModernIconButtonState extends State<ModernIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final semanticLabel =
        widget.semanticLabel ??
        switch (widget.icon) {
          Icons.edit || Icons.edit_outlined => 'Edit',
          Icons.delete || Icons.delete_outline_rounded => 'Delete',
          _ => 'Action',
        };

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          HapticUtils.lightImpact();
          widget.onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.size,
          height: widget.size,
          transform: Matrix4.identity()
            ..scaleByDouble(
              _isPressed ? 0.95 : 1.0,
              _isPressed ? 0.95 : 1.0,
              1.0,
              1.0,
            ),
          decoration: BoxDecoration(
            color: _isPressed
                ? (widget.backgroundColor ?? colors.primary).blend(
                    colors.primaryDark,
                    0.08,
                  )
                : widget.backgroundColor ?? colors.primary,
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.blend(
                  widget.backgroundColor ?? colors.primary,
                  0.18,
                ),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: widget.iconColor ?? colors.textOnPrimary,
            size: widget.size * 0.5,
          ),
        ),
      ),
    );
  }
}

class ModernFAB extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? label;
  final bool extended;

  const ModernFAB({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.label,
    this.extended = false,
  });

  @override
  State<ModernFAB> createState() => _ModernFABState();
}

class _ModernFABState extends State<ModernFAB> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticUtils.lightImpact();
        widget.onPressed();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.symmetric(
          horizontal: widget.extended ? 16 : 14,
          vertical: 14,
        ),
        transform: Matrix4.identity()
          ..scaleByDouble(
            _isPressed ? 0.97 : 1.0,
            _isPressed ? 0.97 : 1.0,
            1.0,
            1.0,
          ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _isPressed
                  ? (widget.backgroundColor ?? colors.primary).blend(
                      colors.primaryDark,
                      0.08,
                    )
                  : widget.backgroundColor ?? colors.primary,
              (widget.backgroundColor ?? colors.primary).blend(
                colors.primaryLight,
                0.35,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.blend(
                widget.backgroundColor ?? colors.primary,
                0.2,
              ),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              color: widget.iconColor ?? colors.textOnPrimary,
              size: 20,
            ),
            if (widget.extended && widget.label != null) ...[
              const SizedBox(width: 10),
              Text(
                widget.label!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: widget.iconColor ?? colors.textOnPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
