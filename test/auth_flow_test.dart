import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/Main/editProfile.dart';
import 'package:parkiwell/routes.dart';
import 'package:parkiwell/singleton.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final singleton = Singleton();
    singleton.firstTime = true;
    singleton.name = '[Name]';
    singleton.email = '[Email]';
  });

  Future<void> pumpAuth(WidgetTester tester, {bool signIn = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        routes: namedRoutes,
        home: EditProfileScreen(startInSignIn: signIn, onBack: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('sign in enforces the legacy 6 character floor', (tester) async {
    await pumpAuth(tester, signIn: true);

    await tester.enterText(
      find.widgetWithText(TextField, 'Enter your password').first,
      'short',
    );
    await tester.tap(find.text('Sign In with Email'));
    await tester.pump();

    expect(find.text('Use at least 6 characters.'), findsOneWidget);
  });

  testWidgets('sign in flags an invalid email next to the field', (
    tester,
  ) async {
    await pumpAuth(tester, signIn: true);

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.text('Sign In with Email'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('password visibility toggle reveals input', (tester) async {
    await pumpAuth(tester, signIn: true);

    final passwordField = find.widgetWithText(TextField, 'Enter your password');
    expect(passwordField, findsOneWidget);
    expect(tester.widget<TextField>(passwordField.first).obscureText, isTrue);

    final visibilityToggle = find.byIcon(Icons.visibility_outlined).first;
    await tester.tap(visibilityToggle);
    await tester.pump();

    expect(tester.widget<TextField>(passwordField.first).obscureText, isFalse);
  });
}
