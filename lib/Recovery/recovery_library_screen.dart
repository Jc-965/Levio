import 'package:flutter/material.dart';
import 'package:parkiwell/singleton.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/recovery_log_sheet.dart';
import '../widgets/recovery_lesson_card.dart';
import '../widgets/tutorial_overlay.dart';

/// Static configuration for a recovery session library (physical exercise or
/// speech practice). The two screens share every behavior; only copy, icons,
/// accent, catalog, and recording callbacks differ.
class RecoveryLibraryConfig {
  const RecoveryLibraryConfig({
    required this.appBarTitle,
    required this.headline,
    required this.intro,
    required this.sectionDescription,
    required this.guideIcon,
    required this.guideTitle,
    required this.guideBody,
    required this.typeLabel,
    required this.typeIcon,
    required this.logTypeLabel,
    required this.logIcon,
    required this.startRoute,
  });

  final String appBarTitle;
  final String headline;
  final String intro;
  final String sectionDescription;
  final IconData guideIcon;
  final String guideTitle;
  final String guideBody;
  final String typeLabel;
  final IconData typeIcon;
  final String logTypeLabel;
  final IconData logIcon;
  final String startRoute;
}

class RecoveryLibraryScreen extends StatefulWidget {
  const RecoveryLibraryScreen({
    super.key,
    required this.config,
    required this.catalog,
    required this.accentOf,
    required this.sessionCountForVideo,
    required this.recordSession,
    this.badgeLabelForVideo,
    this.firstCardKey,
  });

  final RecoveryLibraryConfig config;
  final Map<String, List<String>> catalog;
  final Color Function(AppColors colors) accentOf;
  final int Function(String videoId) sessionCountForVideo;
  final Future<int> Function(String videoId, DateTime? completedAt)
  recordSession;
  final String? Function(String videoId)? badgeLabelForVideo;
  final GlobalKey? firstCardKey;

  @override
  State<RecoveryLibraryScreen> createState() => _RecoveryLibraryScreenState();
}

class _RecoveryLibraryScreenState extends State<RecoveryLibraryScreen>
    with SingleTickerProviderStateMixin {
  final singleton = Singleton();
  late final List<String> _videoIds;
  late final AnimationController _introController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _videoIds = widget.catalog.keys.toList(growable: false);
    singleton.addListener(_onSingletonUpdate);

    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _introController = AnimationController(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      vsync: this,
    )..forward();
    _fade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(_fade);
  }

  @override
  void dispose() {
    singleton.removeListener(_onSingletonUpdate);
    _introController.dispose();
    super.dispose();
  }

  void _onSingletonUpdate() {
    if (mounted) setState(() {});
  }

  void _showGuide() {
    showGuideDialog(
      context,
      icon: widget.config.guideIcon,
      title: widget.config.guideTitle,
      body: widget.config.guideBody,
      footnote: 'Sources are shown on each session card.',
    );
  }

  void _showLoggedSnack(String title, int count) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$title added to your log · $count ${count == 1 ? 'session' : 'sessions'} total',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.accentOf(colors);
    final config = widget.config;

    return TutorialOverlay(
      steps: const [],
      child: Scaffold(
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
          title: Text(config.appBarTitle),
          actions: [
            IconButton(
              tooltip: config.guideTitle,
              onPressed: _showGuide,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LiquidBackground(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.headline,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            config.intro,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.45,
                                ),
                          ),
                          const SizedBox(height: 22),
                          SectionHeading(
                            title: 'Session library',
                            description: config.sectionDescription,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final videoId = _videoIds[index];
                          final data = widget.catalog[videoId]!;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == _videoIds.length - 1 ? 0 : 16,
                            ),
                            child: Container(
                              key: index == 0 ? widget.firstCardKey : null,
                              child: RecoveryLessonCard(
                                title: data[0],
                                description: data[1],
                                duration: data.length > 2 ? data[2] : '',
                                source: data.length > 3 ? data[3] : '',
                                thumbnailUrl:
                                    'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                                typeLabel: config.typeLabel,
                                badgeLabel: widget.badgeLabelForVideo?.call(
                                  videoId,
                                ),
                                typeIcon: config.typeIcon,
                                accent: accent,
                                sessionCount: widget.sessionCountForVideo(
                                  videoId,
                                ),
                                onStart: () {
                                  HapticUtils.cardTap();
                                  singleton.setCurrentUrl(videoId);
                                  Navigator.pushNamed(
                                    context,
                                    config.startRoute,
                                  );
                                },
                                onLog: () async {
                                  final count = await showRecoveryLogSheet(
                                    context: context,
                                    title: data[0],
                                    typeLabel: config.logTypeLabel,
                                    duration: data.length > 2 ? data[2] : '',
                                    icon: config.logIcon,
                                    accent: accent,
                                    onSave: (completedAt) => widget
                                        .recordSession(videoId, completedAt),
                                  );
                                  if (count == null) return;
                                  if (!mounted) return;
                                  _showLoggedSnack(data[0], count);
                                },
                              ),
                            ),
                          );
                        },
                        childCount: _videoIds.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
