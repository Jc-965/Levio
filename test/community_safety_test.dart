import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Singleton singleton;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    singleton = Singleton();
    // The singleton caches prefs across tests; clear explicitly.
    for (final id in (await singleton.blockedUserIds()).toList()) {
      await singleton.unblockCommunityUser(id);
    }
  });

  test('blocking a user persists their id', () async {
    await singleton.blockCommunityUser('user-a');
    await singleton.blockCommunityUser('user-b');

    expect(await singleton.blockedUserIds(), {'user-a', 'user-b'});
  });

  test('blocking is idempotent', () async {
    await singleton.blockCommunityUser('user-a');
    await singleton.blockCommunityUser('user-a');

    expect(await singleton.blockedUserIds(), {'user-a'});
  });

  test('unblocking removes the id', () async {
    await singleton.blockCommunityUser('user-a');
    await singleton.unblockCommunityUser('user-a');

    expect(await singleton.blockedUserIds(), isEmpty);
  });

  test('empty ids are never blocked', () async {
    await singleton.blockCommunityUser('   ');

    expect(await singleton.blockedUserIds(), isEmpty);
  });
}
