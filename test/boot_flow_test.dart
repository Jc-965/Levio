import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/main.dart';
import 'package:parkiwell/singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Singleton().firstTime = true;
  });

  Future<void> advanceThroughSplash(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('splash waits for startup sync before routing', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(MyApp(bootstrap: gate.future));

    await advanceThroughSplash(tester);

    // Sync still pending: stay on splash rather than routing blind.
    expect(find.text('Preparing your care workspace'), findsOneWidget);
    expect(find.text('Create my care plan'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Create my care plan'), findsOneWidget);
  });

  testWidgets('splash gives up on startup sync after the timeout', (
    tester,
  ) async {
    final never = Completer<void>();
    await tester.pumpWidget(MyApp(bootstrap: never.future));

    await advanceThroughSplash(tester);
    expect(find.text('Create my care plan'), findsNothing);

    // Past the 8 second cap the app continues with local data.
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Create my care plan'), findsOneWidget);
  });

  testWidgets('a fast bootstrap never delays the splash hand-off', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(bootstrap: Future<void>.value()));

    await advanceThroughSplash(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Create my care plan'), findsOneWidget);
  });
}
