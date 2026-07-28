import 'package:flutter/material.dart';
import 'package:parkiwell/singleton.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/recovery_log_sheet.dart';
import '../widgets/recovery_lesson_card.dart';

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  State<SpeechScreen> createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen>
    with SingleTickerProviderStateMixin {
  final singleton = Singleton();
  late final List<String> _videoIds;
  late final AnimationController _introController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _videoIds = singleton.speeches.keys.toList(growable: false);
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

  void _showSpeechGuide() {
    showGuideDialog(
      context,
      icon: Icons.record_voice_over_rounded,
      title: 'Speech practice guide',
      body:
          'Practice in a comfortable voice, pause when you need to, and repeat sections at your own pace. Start a video for guidance, then log it once after you finish.',
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
        title: const Text('Speech sessions'),
        actions: [
          IconButton(
            tooltip: 'Speech practice guide',
            onPressed: _showSpeechGuide,
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
                          'Practice with intention',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Choose one guided session. Starting opens the video; logging is a separate action for sessions you have completed.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 22),
                        const SectionHeading(
                          title: 'Session library',
                          description:
                              'Voice strength, articulation, pace, and clarity.',
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
                        final data = singleton.speeches[videoId]!;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == _videoIds.length - 1 ? 0 : 16,
                          ),
                          child: RecoveryLessonCard(
                            title: data[0],
                            description: data[1],
                            duration: data.length > 2 ? data[2] : '',
                            source: data.length > 3 ? data[3] : '',
                            thumbnailUrl:
                                'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                            typeLabel: 'Speech practice',
                            typeIcon: Icons.record_voice_over_rounded,
                            accent: colors.primary,
                            sessionCount: singleton.speechSessionCountForVideo(
                              videoId,
                            ),
                            onStart: () {
                              HapticUtils.cardTap();
                              singleton.setCurrentUrl(videoId);
                              Navigator.pushNamed(context, '/speechAudio');
                            },
                            onLog: () async {
                              final count = await showRecoveryLogSheet(
                                context: context,
                                title: data[0],
                                typeLabel: 'Speech',
                                duration: data.length > 2 ? data[2] : '',
                                icon: Icons.graphic_eq_rounded,
                                accent: colors.primary,
                                onSave: (completedAt) =>
                                    singleton.recordSpeechExerciseSession(
                                      videoId,
                                      completedAt: completedAt,
                                    ),
                              );
                              if (count == null) return;
                              if (!mounted) return;
                              _showLoggedSnack(data[0], count);
                            },
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
    );
  }
}
