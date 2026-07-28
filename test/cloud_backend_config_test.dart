import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/config/backend_config.dart';
import 'package:parkiwell/config/environment.dart';

void main() {
  test('Supabase backend config follows dart defines', () {
    const provider = String.fromEnvironment(
      'BACKEND_PROVIDER',
      defaultValue: 'none',
    );
    const environment = String.fromEnvironment(
      'ENVIRONMENT',
      defaultValue: 'development',
    );
    const supabaseUrl = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: '',
    );
    const supabaseAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );

    switch (environment) {
      case 'testing':
        expect(EnvironmentConfig.current, Environment.testing);
        expect(EnvironmentConfig.isTesting, isTrue);
        break;
      case 'staging':
        expect(EnvironmentConfig.current, Environment.staging);
        expect(EnvironmentConfig.isStaging, isTrue);
        break;
      case 'production':
        expect(EnvironmentConfig.current, Environment.production);
        expect(EnvironmentConfig.isProduction, isTrue);
        break;
      default:
        expect(EnvironmentConfig.current, Environment.development);
    }

    if (provider.toLowerCase() == 'supabase') {
      expect(BackendConfig.provider, BackendProvider.supabase);
      expect(BackendConfig.supabaseUrl, supabaseUrl);
      expect(BackendConfig.supabaseAnonKey, supabaseAnonKey);
      expect(BackendConfig.supabaseUrl, isNotEmpty);
      expect(BackendConfig.supabaseAnonKey, isNotEmpty);
      expect(BackendConfig.isCloudBackendEnabled, isTrue);
    } else {
      expect(BackendConfig.provider, BackendProvider.none);
      expect(BackendConfig.isCloudBackendEnabled, isFalse);
    }
  });
}
