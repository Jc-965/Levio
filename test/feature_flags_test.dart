import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/cloud_backend_service.dart';
import 'package:parkiwell/services/feature_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a flag that has never been fetched uses the caller fallback', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FeatureFlags flags = FeatureFlags();
    await flags.load();

    expect(flags.isEnabled('motion_coach'), isTrue);
    expect(flags.isEnabled('motion_coach', fallback: false), isFalse);
  });

  test('loads the cached flag map from storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FeatureFlags.storageKey: '{"motion_coach": false}',
    });
    final FeatureFlags flags = FeatureFlags();
    await flags.load();

    expect(flags.isEnabled(FeatureFlags.motionCoachKey), isFalse);
  });

  test('a failed refresh keeps the last cached values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FeatureFlags.storageKey: '{"motion_coach": false}',
    });
    final FeatureFlags flags = FeatureFlags();
    // An uninitialized backend has no client, so fetchAppFlags returns
    // null — exactly the offline / backend-down shape.
    await flags.refresh(CloudBackendService());

    expect(flags.isEnabled(FeatureFlags.motionCoachKey), isFalse);
  });

  test('an unreadable cache falls back instead of crashing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FeatureFlags.storageKey: 'not json at all',
    });
    final FeatureFlags flags = FeatureFlags();
    await flags.load();

    expect(flags.isEnabled(FeatureFlags.motionCoachKey), isTrue);
  });
}
