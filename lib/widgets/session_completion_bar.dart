import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import 'recovery_log_sheet.dart';

/// Persistent, single-purpose completion action for recovery video screens.
/// It prevents accidental duplicate logs during the same visit.
class SessionCompletionBar extends StatefulWidget {
  final int sessionCount;
  final String title;
  final String typeLabel;
  final String duration;
  final IconData icon;
  final Color accent;
  final RecoveryLogSave onLog;

  const SessionCompletionBar({
    super.key,
    required this.sessionCount,
    required this.title,
    required this.typeLabel,
    required this.duration,
    required this.icon,
    required this.accent,
    required this.onLog,
  });

  @override
  State<SessionCompletionBar> createState() => _SessionCompletionBarState();
}

class _SessionCompletionBarState extends State<SessionCompletionBar> {
  bool _isSaving = false;
  bool _isLogged = false;
  String? _error;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.sessionCount;
  }

  @override
  void didUpdateWidget(covariant SessionCompletionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isLogged && widget.sessionCount != oldWidget.sessionCount) {
      _count = widget.sessionCount;
    }
  }

  Future<void> _handleLog() async {
    if (_isSaving || _isLogged) return;
    HapticUtils.mediumImpact();
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final nextCount = await showRecoveryLogSheet(
        context: context,
        title: widget.title,
        typeLabel: widget.typeLabel,
        duration: widget.duration,
        icon: widget.icon,
        accent: widget.accent,
        onSave: widget.onLog,
      );
      if (!mounted) return;
      if (nextCount == null) return;
      if (nextCount <= 0) {
        throw StateError('Unable to save session');
      }
      HapticUtils.success();
      setState(() {
        _count = nextCount;
        _isLogged = true;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Session added to your recovery log.')),
        );
    } catch (_) {
      if (!mounted) return;
      HapticUtils.error();
      setState(() {
        _error = 'Could not add this session. Try again.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isLogged ? 'Added to History' : 'Finished this session?',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            _isLogged
                ? '$_count ${_count == 1 ? 'completion' : 'completions'} total'
                : 'Add it once when your practice is complete.',
            key: ValueKey<int>(_count),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
    final action = FilledButton(
      onPressed: _isSaving || _isLogged ? null : _handleLog,
      style: FilledButton.styleFrom(
        backgroundColor: colors.textPrimary,
        foregroundColor: colors.background,
        disabledBackgroundColor: _isLogged
            ? colors.success.withValues(alpha: 0.16)
            : colors.surfaceVariant,
        disabledForegroundColor: _isLogged
            ? colors.success
            : colors.textTertiary,
        minimumSize: const Size(158, 50),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _isSaving
          ? SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.background,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLogged ? Icons.check_rounded : Icons.add_rounded,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Text(_isLogged ? 'Added' : 'Add to History'),
              ],
            ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final stack =
                      constraints.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.2;
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [info, const SizedBox(height: 10), action],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 12),
                      action,
                    ],
                  );
                },
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
            ],
          ),
        ),
      ),
    );
  }
}
