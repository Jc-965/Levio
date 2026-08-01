import 'encrypted_cache_store.dart';
import 'offline_sync_engine.dart';

/// Seals the offline mutation journal at rest.
///
/// Pending health mutations (symptoms, medication events) carry the same
/// sensitivity as the local cache, so they use the same AES-256-GCM key held
/// in the platform keystore. Legacy plaintext journals are migrated to
/// sealed storage on first read.
class EncryptedMutationJournalStore implements MutationJournalStore {
  EncryptedMutationJournalStore(this._inner, this._cacheStore);

  final MutationJournalStore _inner;
  final EncryptedCacheStore _cacheStore;

  @override
  Future<String?> read() async {
    final raw = await _inner.read();
    if (raw == null || raw.isEmpty) return raw;
    final wasPlaintext = !raw.startsWith(EncryptedCacheStore.payloadPrefix);
    final opened = await _cacheStore.open(raw);
    // Undecryptable ciphertext reads as an empty journal rather than
    // feeding garbage into replay.
    if (opened == null) return null;
    if (wasPlaintext && !_cacheStore.keystoreUnavailable) {
      await write(opened);
    }
    return opened;
  }

  @override
  Future<void> write(String encodedJournal) async {
    await _inner.write(await _cacheStore.seal(encodedJournal));
  }

  @override
  Future<void> clear() => _inner.clear();
}
