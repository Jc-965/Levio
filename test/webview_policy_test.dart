import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/utils/webview_policy.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NavigationDecision decide(String url) =>
      decideEmbedNavigation(NavigationRequest(url: url, isMainFrame: true));

  test('nocookie embed hosts may navigate in-app', () {
    expect(
      decide('https://www.youtube-nocookie.com/embed/abc123'),
      NavigationDecision.navigate,
    );
    expect(
      decide('https://youtube-nocookie.com/embed/abc123'),
      NavigationDecision.navigate,
    );
  });

  test('full-tracking youtube.com is pushed out of the in-app view', () {
    expect(
      decide('https://www.youtube.com/watch?v=abc123'),
      NavigationDecision.prevent,
    );
    expect(
      decide('https://m.youtube.com/watch?v=abc123'),
      NavigationDecision.prevent,
    );
  });

  test('arbitrary origins are blocked', () {
    expect(decide('https://evil.example.com/'), NavigationDecision.prevent);
    expect(decide('javascript:alert(1)'), NavigationDecision.prevent);
    expect(decide('not a url'), NavigationDecision.prevent);
  });
}
