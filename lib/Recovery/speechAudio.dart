import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:parkiwell/singleton.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../utils/webview_policy.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';
import '../widgets/session_completion_bar.dart';

class SpeechAudio extends StatefulWidget {
  const SpeechAudio({super.key});

  @override
  State<SpeechAudio> createState() => _SpeechAudioState();
}

class _SpeechAudioState extends State<SpeechAudio> {
  final singleton = Singleton();
  WebViewController? _webViewController;
  String? _videoId;
  bool _isVideoLoading = true;

  String get _youtubeUrl =>
      'https://www.youtube.com/watch?v=${_videoId ?? singleton.currentURL}';

  @override
  void initState() {
    super.initState();
    // Keep the screen awake during a guided session; users with impaired
    // fine motor control cannot quickly re-wake a locked device mid-set.
    WakelockPlus.enable();
    _videoId = singleton.normalizeYouTubeVideoId(singleton.currentURL);
    if (_videoId != null && !kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: decideEmbedNavigation,
            onPageStarted: (_) {
              if (!mounted) return;
              setState(() => _isVideoLoading = true);
            },
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _isVideoLoading = false);
            },
            onWebResourceError: (_) {
              if (!mounted) return;
              setState(() => _webViewController = null);
            },
          ),
        )
        // The nocookie embed player avoids YouTube tracking cookies inside
        // a disease-specific app.
        ..loadRequest(
          Uri.https('www.youtube-nocookie.com', '/embed/$_videoId', {
            'playsinline': '1',
            'controls': '1',
            'rel': '0',
          }),
        );
    } else {
      _isVideoLoading = false;
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<int> _recordSession(DateTime completedAt) async {
    final videoId = _videoId ?? singleton.currentURL;
    final normalized = singleton.normalizeYouTubeVideoId(videoId);
    if (normalized == null) {
      throw StateError('Invalid speech session link');
    }
    return singleton.recordSpeechExerciseSession(
      normalized,
      completedAt: completedAt,
    );
  }

  Future<void> _openInAppBrowser() async {
    if (_videoId == null) return;
    final uri = Uri.parse(_youtubeUrl);
    await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    );
  }

  Future<void> _openInYouTube() async {
    if (_videoId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This video link appears invalid.'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }

    final uri = Uri.parse(_youtubeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unable to open YouTube link'),
        backgroundColor: context.colors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final speechData = singleton.speeches[singleton.currentURL];
    final source = speechData != null && speechData.length > 3
        ? speechData[3]
        : '';
    final sessionCount = singleton.speechSessionCountForVideo(
      singleton.currentURL,
    );

    if (speechData == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Speech Therapy',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Container(
          color: colors.background,
          child: const Center(child: Text('Video not found')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            HapticUtils.lightImpact();
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          'Speech Therapy',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            onPressed: () {
              HapticUtils.lightImpact();
              _openInYouTube();
            },
            icon: Icon(
              Icons.open_in_new_rounded,
              color: colors.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LiquidBackground(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                speechData[0],
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ModernCard(
                padding: const EdgeInsets.all(14),
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session focus',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      speechData[1],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    if (source.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        source,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Guided speech session',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              (_webViewController != null)
                  ? RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: WebViewWidget(
                                controller: _webViewController!,
                              ),
                            ),
                            if (_isVideoLoading)
                              Positioned.fill(
                                child: ColoredBox(
                                  color: colors.surface.withValues(alpha: 0.92),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: colors.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Loading video...',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colors.textSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kIsWeb
                                ? 'Continue in YouTube'
                                : 'Unable to load video in-app',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            kIsWeb
                                ? 'Guided videos open in YouTube on the web. Your completion control stays here when you return.'
                                : 'Open this speech session directly in YouTube.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          if (kIsWeb)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _openInYouTube,
                                icon: const Icon(Icons.open_in_new_rounded),
                                label: const Text('Play video'),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _openInAppBrowser,
                                    icon: const Icon(
                                      Icons.ondemand_video_rounded,
                                    ),
                                    label: const Text('Play in App'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _openInYouTube,
                                    icon: const Icon(Icons.open_in_new_rounded),
                                    label: const Text('Open YouTube'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
              const SizedBox(height: 18),
              GlassSurface(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pause and repeat sections as needed. The completion control stays available below when you finish.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SessionCompletionBar(
        sessionCount: sessionCount,
        title: speechData[0],
        typeLabel: 'Speech',
        duration: speechData.length > 2 ? speechData[2] : '',
        icon: Icons.graphic_eq_rounded,
        accent: colors.primary,
        onLog: _recordSession,
      ),
    );
  }
}
