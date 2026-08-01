import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parkiwell/Main/editProfile.dart';
import 'package:parkiwell/navbar.dart';
import 'package:parkiwell/singleton.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies the auth screen against the REAL cloud backend and captures
/// screenshots of the provider buttons. Must be run with the backend
/// configured or the social buttons will not render:
///
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/auth_screens_test.dart \
///     --dart-define-from-file=.env.local \
///     -d "iPhone 17 Pro Max"
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auth screen shows providers and signs in against cloud', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('parkiwell_main_tutorial_completed_v1', true);

    final singleton = Singleton();
    await singleton.initialize(isProduction: false);

    expect(
      singleton.isCloudConfigured,
      isTrue,
      reason: 'Run with --dart-define-from-file=.env.local',
    );

    var completed = false;
    Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      home: home,
    );

    await tester.pumpWidget(
      app(
        EditProfileScreen(
          startInSignIn: true,
          onComplete: () => completed = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(milliseconds: 100));

    // The two provider buttons must be visible on the sign-in stage.
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Sign In with Google'), findsOneWidget);
    expect(find.text('Sign In with Email'), findsOneWidget);
    await binding.takeScreenshot('auth-signin');

    // Live sign-in with the seeded demo account.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'jcscen+parkiwell-demo@gmail.com');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(fields.at(1), 'ParkiWell-Demo-2026!');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Sign In with Email'));

    // Real network round trips: poll up to 30s for completion.
    for (var i = 0; i < 60 && !completed; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      completed,
      isTrue,
      reason: 'Cloud sign-in did not complete within 30s',
    );

    // Land on the real Home tab fed by cloud-synced records.
    await tester.pumpWidget(app(const Navbar()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(
      find.textContaining('Alex'),
      findsWidgets,
      reason: 'Cloud profile name should appear on Home',
    );
    await binding.takeScreenshot('auth-home-cloud');
  });
}
