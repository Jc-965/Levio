import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Singleton singleton;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    singleton = Singleton();
    singleton.name = 'Pat Example';
    // The singleton caches its SharedPreferences instance, so reset the
    // preference explicitly rather than relying on the mock store reset.
    await singleton.setCommunityUseRealName(false);
  });

  test('community posts use a private alias by default', () async {
    final displayName = await singleton.communityDisplayName();

    expect(displayName, isNot('Pat Example'));
    expect(displayName, startsWith('Member-'));
  });

  test('the alias is stable across calls', () async {
    final first = await singleton.communityDisplayName();
    final second = await singleton.communityDisplayName();

    expect(second, first);
  });

  test('real name appears only after opt-in', () async {
    await singleton.setCommunityUseRealName(true);

    expect(await singleton.communityDisplayName(), 'Pat Example');
    expect(await singleton.getCommunityUseRealName(), isTrue);
  });

  test('opting back out returns to the same alias', () async {
    final alias = await singleton.communityDisplayName();
    await singleton.setCommunityUseRealName(true);
    await singleton.setCommunityUseRealName(false);

    expect(await singleton.communityDisplayName(), alias);
  });

  test('opt-in without a usable name still falls back to the alias', () async {
    singleton.name = '[Name]';
    await singleton.setCommunityUseRealName(true);

    expect(await singleton.communityDisplayName(), startsWith('Member-'));
  });
}
