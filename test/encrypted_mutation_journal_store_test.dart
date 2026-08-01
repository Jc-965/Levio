import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/encrypted_cache_store.dart';
import 'package:parkiwell/services/encrypted_mutation_journal_store.dart';
import 'package:parkiwell/services/offline_sync_engine.dart';

class _MemoryJournalStore implements MutationJournalStore {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String encodedJournal) async {
    stored = encodedJournal;
  }

  @override
  Future<void> clear() async {
    stored = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryJournalStore inner;
  late EncryptedMutationJournalStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    inner = _MemoryJournalStore();
    store = EncryptedMutationJournalStore(inner, EncryptedCacheStore());
  });

  test('journal is sealed at rest and round-trips', () async {
    const journal = '[{"kind":"log","payload":{"symptom":"Tremor"}}]';
    await store.write(journal);

    expect(inner.stored, startsWith(EncryptedCacheStore.payloadPrefix));
    expect(inner.stored, isNot(contains('Tremor')));
    expect(await store.read(), journal);
  });

  test('legacy plaintext journal is readable and migrated to sealed', () async {
    const legacy = '[{"kind":"log","payload":{"symptom":"Stiffness"}}]';
    inner.stored = legacy;

    expect(await store.read(), legacy);
    expect(inner.stored, startsWith(EncryptedCacheStore.payloadPrefix));
    expect(await store.read(), legacy);
  });

  test('empty journal passes through', () async {
    expect(await store.read(), isNull);
  });

  test('tampered journal reads as empty instead of corrupt replay', () async {
    await store.write('[{"kind":"log"}]');
    inner.stored =
        '${inner.stored!.substring(0, inner.stored!.length - 4)}XXXX';

    expect(await store.read(), isNull);
  });

  test('clear delegates to the inner store', () async {
    await store.write('[]');
    await store.clear();

    expect(inner.stored, isNull);
  });
}
