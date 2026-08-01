import 'dart:async';

import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const Set<String> _allowedEmbedHosts = {
  // nocookie only: allowing youtube.com here let one tap on the player's
  // title navigate the in-app WebView to full-tracking YouTube, defeating
  // the whole point of the nocookie embed.
  'www.youtube-nocookie.com',
  'youtube-nocookie.com',
};

/// Allows only YouTube embed hosts inside the in-app player. Anything else
/// (link taps, redirects, ads) opens in the external browser, so the app's
/// WebView can never be steered to an arbitrary origin.
NavigationDecision decideEmbedNavigation(NavigationRequest request) {
  final uri = Uri.tryParse(request.url);
  final host = uri?.host.toLowerCase() ?? '';
  if (_allowedEmbedHosts.contains(host)) {
    return NavigationDecision.navigate;
  }
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    unawaited(
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
        // Launcher unavailable (tests, restricted profiles): the
        // navigation stays blocked either way.
        return false;
      }),
    );
  }
  return NavigationDecision.prevent;
}
