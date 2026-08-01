import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/encrypted_cache_store.dart';

void main() {
  testWidgets('seal inside testWidgets resolves', (tester) async {
    final store = EncryptedCacheStore();
    final sealed = await store
        .seal('hello')
        .timeout(const Duration(seconds: 5), onTimeout: () => 'TIMEOUT');
    debugPrint('SEAL RESULT: $sealed unavailable=${store.keystoreUnavailable}');
    expect(sealed, isNot('TIMEOUT'));
  });
}
