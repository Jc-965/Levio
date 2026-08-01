import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/backend_config.dart';
import 'app_logger.dart';
import 'secure_session_storage.dart';

class CloudAuthProfile {
  final String userId;
  final String? email;
  final String? fullName;
  final String? avatarUrl;

  const CloudAuthProfile({
    required this.userId,
    this.email,
    this.fullName,
    this.avatarUrl,
  });
}

class CloudBackendService {
  static final CloudBackendService _instance = CloudBackendService._internal();
  factory CloudBackendService() => _instance;

  CloudBackendService._internal();

  final AppLogger _logger = AppLogger();

  SupabaseClient? _client;
  bool _initialized = false;
  bool _enabled = false;
  String? _cloudUserId;
  String? _lastInitializationError;

  final StreamController<CloudAuthProfile> _verifiedSignIns =
      StreamController<CloudAuthProfile>.broadcast();
  final StreamController<void> _passwordRecoveryEvents =
      StreamController<void>.broadcast();
  bool _passwordRecoveryPending = false;
  // Lives for the whole app session alongside this singleton.
  // ignore: cancel_subscriptions
  StreamSubscription<AuthState>? _authStateSubscription;

  /// Emits whenever a non-anonymous session is established outside an
  /// explicit sign-in call (e.g. the email verification deep link).
  Stream<CloudAuthProfile> get verifiedSignIns => _verifiedSignIns.stream;
  Stream<void> get passwordRecoveryEvents => _passwordRecoveryEvents.stream;
  bool get isPasswordRecoveryPending => _passwordRecoveryPending;

  void _ensureAuthStateListener() {
    if (_authStateSubscription != null || _client == null) return;
    _authStateSubscription = _client!.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryPending = true;
        _passwordRecoveryEvents.add(null);
        return;
      }
      if (event.event != AuthChangeEvent.signedIn) return;
      final user = event.session?.user;
      if (user == null || user.isAnonymous) return;
      final profile = _profileFromUser(user);
      _cloudUserId = profile.userId;
      _enabled = true;
      _lastInitializationError = null;
      _verifiedSignIns.add(profile);
    });
  }

  bool get isConfigured => BackendConfig.isCloudBackendEnabled;
  bool get hasActiveSession => _client?.auth.currentSession != null;
  bool get isEnabled =>
      _enabled && _client != null && _cloudUserId != null && hasActiveSession;
  String? get cloudUserId => _cloudUserId;
  String? get lastInitializationError => _lastInitializationError;

  String get statusDescription {
    if (!isConfigured) {
      return 'Cloud backend not configured';
    }
    if (isEnabled) {
      return 'Secure cloud sync connected';
    }
    if (_lastInitializationError != null) {
      return 'Cloud unavailable';
    }
    return 'Connecting...';
  }

  bool _isTransientError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }

    if (error is PostgrestException) {
      final code = error.code ?? '';
      if (code.startsWith('08') ||
          code == '40001' ||
          code == '40P01' ||
          code == '53300' ||
          code == '57014') {
        return true;
      }
    }

    final message = error.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('temporar') ||
        message.contains('network');
  }

  Future<T> _withRetry<T>(
    String operationName,
    Future<T> Function() operation, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await operation();
      } catch (e, stackTrace) {
        lastError = e;

        final canRetry = attempt < maxAttempts && _isTransientError(e);
        if (!canRetry) {
          _logger.error(
            'Cloud $operationName failed (attempt $attempt/$maxAttempts)',
            e,
            stackTrace,
          );
          rethrow;
        }

        final delayMs = 250 * (1 << (attempt - 1));
        _logger.warning(
          'Cloud $operationName transient failure (attempt $attempt/$maxAttempts), retrying in ${delayMs}ms',
          e,
          stackTrace,
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    throw lastError ?? Exception('Cloud $operationName failed');
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!isConfigured) {
      _lastInitializationError = 'Cloud backend not configured.';
      _logger.warning('Cloud backend is required but not configured.');
      return;
    }

    try {
      // If already initialized by another part of the app, reuse the client.
      _client = Supabase.instance.client;
      _ensureAuthStateListener();
      await _establishAuthenticatedSession();
      _enabled = _cloudUserId != null;
      _logger.info(
        _enabled
            ? 'Cloud backend connected to existing Supabase client.'
            : 'Supabase client found, but no authenticated session was available.',
      );
      return;
    } catch (_) {
      // Fallthrough to explicit initialize.
    }

    try {
      await Supabase.initialize(
        url: BackendConfig.supabaseUrl,
        publishableKey: BackendConfig.supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: true,
          // The refresh token unlocks all server-side health data; keep it
          // in the keystore, not plaintext SharedPreferences.
          localStorage: SecureSessionStorage(),
        ),
      );

      _client = Supabase.instance.client;
      _ensureAuthStateListener();
      await _establishAuthenticatedSession();
      _enabled = _cloudUserId != null;

      if (_enabled) {
        _logger.info('Cloud backend initialized with Supabase.');
      } else {
        _lastInitializationError =
            'Supabase is configured but authentication failed.';
      }
    } catch (e, stackTrace) {
      _enabled = false;
      _lastInitializationError = e.toString();
      _logger.error('Failed to initialize cloud backend', e, stackTrace);
    }
  }

  Future<void> _establishAuthenticatedSession() async {
    if (_client == null) return;

    try {
      final existingSession = _client!.auth.currentSession;
      if (existingSession != null) {
        _cloudUserId = existingSession.user.id;
        _lastInitializationError = null;
        return;
      }

      final authResponse = await _client!.auth.signInAnonymously();
      _cloudUserId = authResponse.user?.id;
      _lastInitializationError = null;

      if (_cloudUserId == null) {
        _logger.warning(
          'Anonymous cloud session could not be established. '
          'Enable anonymous auth in Supabase Auth settings.',
        );
      }
    } catch (e, stackTrace) {
      _cloudUserId = null;
      _lastInitializationError = e.toString();
      _logger.error('Cloud authentication failed', e, stackTrace);
    }
  }

  CloudAuthProfile _profileFromUser(User user) {
    final metadata = user.userMetadata ?? <String, dynamic>{};
    final fullName =
        (metadata['full_name'] ?? metadata['name'] ?? metadata['display_name'])
            ?.toString()
            .trim();
    final avatarUrl = metadata['avatar_url']?.toString().trim();

    return CloudAuthProfile(
      userId: user.id,
      email: user.email?.trim(),
      fullName: (fullName != null && fullName.isNotEmpty) ? fullName : null,
      avatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
    );
  }

  bool _isGoogleUser(User user) {
    final provider = user.appMetadata['provider']?.toString().toLowerCase();
    if (provider == 'google') return true;

    final providers = user.appMetadata['providers'];
    if (providers is List) {
      return providers
          .map((value) => value.toString().toLowerCase())
          .contains('google');
    }

    return false;
  }

  Future<CloudAuthProfile?> signInWithGoogle() async {
    if (!isConfigured) {
      _lastInitializationError =
          'Cloud backend is not configured for Google sign-in.';
      return null;
    }

    if (_client == null) {
      await initialize();
    }

    if (_client == null) return null;

    try {
      final existingUser = _client!.auth.currentUser;
      if (existingUser != null && _isGoogleUser(existingUser)) {
        final profile = _profileFromUser(existingUser);
        _cloudUserId = profile.userId;
        _enabled = true;
        _lastInitializationError = null;
        return profile;
      }

      final initialUserId = existingUser?.id;
      final authStream = _client!.auth.onAuthStateChange;
      late final StreamSubscription<AuthState> subscription;
      final completer = Completer<CloudAuthProfile?>();

      subscription = authStream.listen((event) {
        final user = event.session?.user;
        if (user == null) return;
        if (user.id == initialUserId && !_isGoogleUser(user)) return;
        if (!_isGoogleUser(user)) return;

        if (!completer.isCompleted) {
          completer.complete(_profileFromUser(user));
        }
      });

      final CloudAuthProfile? profile;
      try {
        final launched = await _client!.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: BackendConfig.supabaseAuthRedirectUrl,
        );

        if (!launched) return null;

        profile = await completer.future.timeout(
          const Duration(seconds: 25),
          onTimeout: () {
            final user = _client!.auth.currentUser;
            if (user != null && _isGoogleUser(user)) {
              return _profileFromUser(user);
            }
            return null;
          },
        );
      } finally {
        await subscription.cancel();
      }

      if (profile != null) {
        _cloudUserId = profile.userId;
        _enabled = true;
        _lastInitializationError = null;
      }

      return profile;
    } catch (e, stackTrace) {
      _lastInitializationError = e.toString();
      _logger.error('Google sign-in failed', e, stackTrace);
      return null;
    }
  }

  /// Cryptographically random nonce for the Apple ID token exchange; the
  /// SHA-256 digest goes to Apple and the raw value to Supabase so the token
  /// can only be redeemed by this sign-in attempt.
  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  Future<CloudAuthProfile?> signInWithApple() async {
    if (!isConfigured) {
      _lastInitializationError =
          'Cloud backend is not configured for Apple sign-in.';
      return null;
    }

    if (_client == null) {
      await initialize();
    }

    if (_client == null) return null;

    try {
      final rawNonce = _generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('Apple did not return an identity token.');
      }

      final response = await _client!.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final user = response.user;
      if (user == null) return null;

      var profile = _profileFromUser(user);

      // Apple shares the user's name only on the very first authorization,
      // and it never appears in the token metadata — capture it now.
      final appleName = [
        credential.givenName?.trim() ?? '',
        credential.familyName?.trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      if ((profile.fullName == null || profile.fullName!.isEmpty) &&
          appleName.isNotEmpty) {
        profile = CloudAuthProfile(
          userId: profile.userId,
          email: profile.email,
          fullName: appleName,
          avatarUrl: profile.avatarUrl,
        );
      }

      _cloudUserId = profile.userId;
      _enabled = true;
      _lastInitializationError = null;
      return profile;
    } on SignInWithAppleAuthorizationException catch (e) {
      // The user closing the sheet is not an error.
      if (e.code == AuthorizationErrorCode.canceled) return null;
      _lastInitializationError = e.toString();
      _logger.error('Apple sign-in failed', e, StackTrace.current);
      return null;
    } catch (e, stackTrace) {
      _lastInitializationError = e.toString();
      _logger.error('Apple sign-in failed', e, stackTrace);
      return null;
    }
  }

  Future<CloudAuthProfile?> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) {
      _lastInitializationError =
          'Cloud backend is not configured for email sign-up.';
      return null;
    }
    if (_client == null) {
      await initialize();
    }
    if (_client == null) return null;

    try {
      final response = await _client!.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: BackendConfig.supabaseAuthRedirectUrl,
      );
      // Only trust the session returned by the sign-up itself. Falling back
      // to currentSession can pick up the anonymous bootstrap session, which
      // then fails RLS when writing rows for the new account.
      final session = response.session;
      if (session == null) {
        _cloudUserId = null;
        _enabled = false;
        _lastInitializationError =
            'Check your email for a verification link, then sign in to finish setting up your account.';
        return null;
      }

      final user = response.user ?? session.user;
      final profile = _profileFromUser(user);
      _cloudUserId = profile.userId;
      _enabled = true;
      _lastInitializationError = null;
      return profile;
    } catch (e, stackTrace) {
      _lastInitializationError = e.toString();
      _logger.error('Email sign-up failed', e, stackTrace);
      return null;
    }
  }

  Future<CloudAuthProfile?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) {
      _lastInitializationError =
          'Cloud backend is not configured for email sign-in.';
      return null;
    }
    if (_client == null) {
      await initialize();
    }
    if (_client == null) return null;

    try {
      final response = await _client!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final session = response.session;
      final user = response.user ?? session?.user;
      if (session == null || user == null) {
        _cloudUserId = null;
        _enabled = false;
        _lastInitializationError =
            'Sign in completed, but no authenticated session was available.';
        return null;
      }
      final profile = _profileFromUser(user);
      _cloudUserId = profile.userId;
      _enabled = true;
      _lastInitializationError = null;
      return profile;
    } catch (e, stackTrace) {
      _lastInitializationError = e.toString();
      _logger.error('Email sign-in failed', e, stackTrace);
      return null;
    }
  }

  Future<bool?> isCurrentUserEmailVerified() async {
    if (!isConfigured) return null;
    if (_client == null) {
      await initialize();
    }
    final user = _client?.auth.currentUser;
    if (user == null) return null;
    return user.emailConfirmedAt != null;
  }

  Future<bool> resendEmailVerification(String email) async {
    if (!isConfigured) return false;
    if (_client == null) {
      await initialize();
    }
    if (_client == null) return false;

    try {
      await _client!.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: BackendConfig.supabaseAuthRedirectUrl,
      );
      return true;
    } catch (e, stackTrace) {
      _logger.error('Resend verification failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    if (!isConfigured) {
      _lastInitializationError =
          'Cloud backend is not configured for password recovery.';
      return false;
    }
    if (_client == null) {
      await initialize();
    }
    if (_client == null) return false;

    try {
      await _client!.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: BackendConfig.supabaseAuthRedirectUrl,
      );
      _lastInitializationError = null;
      return true;
    } catch (e, stackTrace) {
      _lastInitializationError = e.toString();
      _logger.error('Password reset request failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> updatePassword(String password) async {
    if (_client == null || _client!.auth.currentSession == null) {
      _lastInitializationError =
          'The password recovery link has expired. Request a new link.';
      return false;
    }

    try {
      final response = await _client!.auth.updateUser(
        UserAttributes(password: password),
      );
      if (response.user == null) {
        _lastInitializationError = 'The password could not be updated.';
        return false;
      }
      _passwordRecoveryPending = false;
      _lastInitializationError = null;
      return true;
    } catch (e, stackTrace) {
      _lastInitializationError = e.toString();
      _logger.error('Password update failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> signOut() async {
    if (_client == null) return false;

    try {
      await _client!.auth.signOut();
      _cloudUserId = null;
      _enabled = false;
      await _establishAuthenticatedSession();
      _enabled = _cloudUserId != null;
      _lastInitializationError = null;
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud sign out failed', e, stackTrace);
      return false;
    }
  }

  String? _effectiveUserId(String? fallbackId) {
    return _cloudUserId ?? fallbackId;
  }

  Future<void> _deleteByUserIfExists(String table, String userId) async {
    try {
      await _client!.from(table).delete().eq('user_id', userId);
    } on PostgrestException catch (e) {
      if (e.code == '42P01') {
        _logger.warning('Table $table not found; skipping delete.');
        return;
      }
      rethrow;
    }
  }

  Future<bool> upsertUser({
    required String id,
    required String name,
    required int age,
    String? profileImage,
    String? email,
  }) async {
    if (!isEnabled) return false;

    try {
      final userId = _effectiveUserId(id);
      if (userId == null) return false;

      await _client!.from('users').upsert(<String, dynamic>{
        'id': userId,
        'name': name,
        'email': email,
        'age': age,
        'profile_image': profileImage,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud upsert user failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> deleteUser(String id) async {
    if (!isEnabled) return false;

    try {
      final userId = _effectiveUserId(id);
      if (userId == null) return false;

      await _deleteByUserIfExists('community_group_memberships', userId);
      await _deleteByUserIfExists('community_post_likes', userId);
      await _deleteByUserIfExists('community_comments', userId);
      await _deleteByUserIfExists('community_posts', userId);
      await _deleteByUserIfExists('sync_tombstones', userId);
      await _deleteByUserIfExists('medication_events', userId);
      await _deleteByUserIfExists('recovery_sessions', userId);
      await _deleteByUserIfExists('logs', userId);
      await _deleteByUserIfExists('schedules', userId);
      await _client!.from('users').delete().eq('id', userId);
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud delete user failed', e, stackTrace);
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUser(String id) async {
    if (!isEnabled) return null;

    try {
      final userId = _effectiveUserId(id);
      if (userId == null) return null;

      final result = await _withRetry<Map<String, dynamic>?>(
        'get user',
        () async {
          return _client!.from('users').select().eq('id', userId).maybeSingle();
        },
      );
      return result;
    } catch (e, stackTrace) {
      _logger.error('Cloud get user failed', e, stackTrace);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getLogs(String userId) async {
    if (!isEnabled) return <Map<String, dynamic>>[];

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return <Map<String, dynamic>>[];

      final result = await _withRetry<List<dynamic>>('get logs', () async {
        return _client!
            .from('logs')
            .select()
            .eq('user_id', effectiveUserId)
            .order('created_at', ascending: false);
      });
      return List<Map<String, dynamic>>.from(result);
    } catch (e, stackTrace) {
      _logger.error('Cloud get logs failed', e, stackTrace);
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getSchedules(String userId) async {
    if (!isEnabled) return <Map<String, dynamic>>[];

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return <Map<String, dynamic>>[];

      final result = await _withRetry<List<dynamic>>('get schedules', () async {
        return _client!
            .from('schedules')
            .select()
            .eq('user_id', effectiveUserId)
            .order('created_at', ascending: false);
      });
      return List<Map<String, dynamic>>.from(result);
    } catch (e, stackTrace) {
      _logger.error('Cloud get schedules failed', e, stackTrace);
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getRecoverySessions(String userId) async {
    if (!isEnabled) return <Map<String, dynamic>>[];

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return <Map<String, dynamic>>[];

      final result = await _withRetry<List<dynamic>>(
        'get recovery sessions',
        () async {
          return _client!
              .from('recovery_sessions')
              .select()
              .eq('user_id', effectiveUserId)
              .order('completed_at', ascending: false);
        },
      );
      return List<Map<String, dynamic>>.from(result);
    } catch (e, stackTrace) {
      _logger.error('Cloud get recovery sessions failed', e, stackTrace);
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getMedicationEvents(String userId) async {
    if (!isEnabled) return <Map<String, dynamic>>[];

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return <Map<String, dynamic>>[];

      final result = await _withRetry<List<dynamic>>(
        'get medication events',
        () async {
          return _client!
              .from('medication_events')
              .select()
              .eq('user_id', effectiveUserId)
              .order('scheduled_at', ascending: false);
        },
      );
      return List<Map<String, dynamic>>.from(result);
    } catch (e, stackTrace) {
      _logger.error('Cloud get medication events failed', e, stackTrace);
      return <Map<String, dynamic>>[];
    }
  }

  Future<Set<String>> applyHealthMutations(
    List<Map<String, dynamic>> mutations,
  ) async {
    if (!isEnabled || mutations.isEmpty) return <String>{};

    try {
      final result = await _withRetry<dynamic>(
        'apply health mutation batch',
        () => _client!.rpc(
          'apply_health_mutations',
          params: <String, dynamic>{'p_mutations': mutations},
        ),
      );
      if (result is List) {
        return result
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toSet();
      }
      return <String>{};
    } catch (e, stackTrace) {
      _logger.error('Cloud mutation batch failed', e, stackTrace);
      return <String>{};
    }
  }

  Future<bool> saveLog({
    required String id,
    required String userId,
    required String title,
    required String data,
    required String time,
    required String symptom,
    required String severity,
  }) async {
    if (!isEnabled) return false;

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return false;

      await _withRetry<void>('save log', () async {
        await _client!.from('logs').upsert(<String, dynamic>{
          'id': id,
          'user_id': effectiveUserId,
          'title': title,
          'data': data,
          'event_time': time,
          'symptom': symptom,
          'severity': severity,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud save log failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> deleteLog(String id) async {
    if (!isEnabled) return false;
    try {
      await _withRetry<void>('delete log', () async {
        await _client!.from('logs').delete().eq('id', id);
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud delete log failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> saveSchedule({
    required String id,
    required String userId,
    required String title,
    required String data,
    required String days,
    required String details,
  }) async {
    if (!isEnabled) return false;

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return false;

      await _withRetry<void>('save schedule', () async {
        await _client!.from('schedules').upsert(<String, dynamic>{
          'id': id,
          'user_id': effectiveUserId,
          'title': title,
          'data': data,
          'days': days,
          'details': details,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud save schedule failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> saveRecoverySession({
    required String id,
    required String userId,
    required String type,
    required String videoId,
    required String title,
    required String completedAt,
  }) async {
    if (!isEnabled) return false;

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return false;

      await _withRetry<void>('save recovery session', () async {
        await _client!.from('recovery_sessions').upsert(<String, dynamic>{
          'id': id,
          'user_id': effectiveUserId,
          'type': type,
          'video_id': videoId,
          'title': title,
          'completed_at': completedAt,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud save recovery session failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> deleteRecoverySession(String id) async {
    if (!isEnabled) return false;
    try {
      await _withRetry<void>('delete recovery session', () async {
        await _client!.from('recovery_sessions').delete().eq('id', id);
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud delete recovery session failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> deleteSchedule(String id) async {
    if (!isEnabled) return false;
    try {
      await _withRetry<void>('delete schedule', () async {
        await _client!.from('schedules').delete().eq('id', id);
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud delete schedule failed', e, stackTrace);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getCommunityPosts({
    int limit = 100,
  }) async {
    if (!isEnabled) return <Map<String, dynamic>>[];

    try {
      final result = await _withRetry<List<dynamic>>(
        'get community posts',
        () async {
          return _client!
              .from('community_posts')
              .select()
              .order('created_at', ascending: false)
              .limit(limit);
        },
      );
      return List<Map<String, dynamic>>.from(result);
    } catch (e, stackTrace) {
      _logger.error('Cloud get posts failed', e, stackTrace);
      return <Map<String, dynamic>>[];
    }
  }

  Future<Set<String>> getLikedPostIds({
    required String userId,
    required List<String> postIds,
  }) async {
    if (!isEnabled || postIds.isEmpty) return <String>{};

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return <String>{};

      final result = await _withRetry<List<dynamic>>(
        'get liked post ids',
        () async {
          return _client!
              .from('community_post_likes')
              .select('post_id')
              .eq('user_id', effectiveUserId)
              .inFilter('post_id', postIds);
        },
      );

      return result
          .map((row) => row['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e, stackTrace) {
      _logger.error('Cloud get liked posts failed', e, stackTrace);
      return <String>{};
    }
  }

  Future<bool> saveCommunityPost({
    required String id,
    required String userId,
    required String userName,
    required String content,
    String? category,
    String? profileImage,
  }) async {
    if (!isEnabled) return false;

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return false;

      await _withRetry<void>('save community post', () async {
        await _client!.from('community_posts').upsert(<String, dynamic>{
          'id': id,
          'user_id': effectiveUserId,
          'user_name': userName,
          'profile_image': profileImage,
          'content': content,
          'category': category,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud save post failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> updateCommunityPost({
    required String postId,
    required String content,
    String? category,
  }) async {
    if (!isEnabled) return false;

    try {
      final result = await _withRetry<Map<String, dynamic>?>(
        'update community post',
        () async {
          return _client!
              .from('community_posts')
              .update(<String, dynamic>{
                'content': content,
                'category': category,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', postId)
              .select('id')
              .maybeSingle();
        },
      );

      return result != null;
    } catch (e, stackTrace) {
      _logger.error('Cloud update post failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> deleteCommunityPost(String postId) async {
    if (!isEnabled) return false;

    try {
      final deleted = await _withRetry<Map<String, dynamic>?>(
        'delete community post',
        () async {
          return _client!
              .from('community_posts')
              .delete()
              .eq('id', postId)
              .select('id')
              .maybeSingle();
        },
      );
      return deleted != null;
    } catch (e, stackTrace) {
      _logger.error('Cloud delete post failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> incrementPostLike(String postId) async {
    if (!isEnabled) return false;

    try {
      await _withRetry<void>('increment post like via rpc', () async {
        await _client!.rpc(
          'increment_post_like',
          params: {'p_post_id': postId},
        );
      });
      return true;
    } catch (e, stackTrace) {
      _logger.warning(
        'Cloud like RPC failed, falling back to direct update',
        e,
        stackTrace,
      );
    }

    // Compatibility fallback for older schemas where the RPC does not exist.
    try {
      final record = await _withRetry<Map<String, dynamic>?>(
        'fetch post likes fallback',
        () async {
          return _client!
              .from('community_posts')
              .select('likes')
              .eq('id', postId)
              .maybeSingle();
        },
      );
      if (record == null) return false;
      final currentLikes = (record['likes'] as num?)?.toInt() ?? 0;
      final updated = await _withRetry<Map<String, dynamic>?>(
        'increment post like fallback',
        () async {
          return _client!
              .from('community_posts')
              .update(<String, dynamic>{
                'likes': currentLikes + 1,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', postId)
              .select('id')
              .maybeSingle();
        },
      );
      return updated != null;
    } catch (e, stackTrace) {
      _logger.error('Cloud like post failed', e, stackTrace);
      return false;
    }
  }

  Future<bool?> likeCommunityPost({
    required String postId,
    required String userId,
  }) async {
    if (!isEnabled) return null;

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return null;

      await _withRetry<void>('insert community post like', () async {
        await _client!.from('community_post_likes').insert(<String, dynamic>{
          'post_id': postId,
          'user_id': effectiveUserId,
        });
      });
    } on PostgrestException catch (e, stackTrace) {
      if (e.code == '23505') {
        return false;
      }
      _logger.error('Cloud like insert failed', e, stackTrace);
      return null;
    } catch (e, stackTrace) {
      _logger.error('Cloud like insert failed', e, stackTrace);
      return null;
    }

    final incremented = await incrementPostLike(postId);
    if (!incremented) return null;
    return true;
  }

  /// Records a unique per-user report; the RPC hides the post after three
  /// distinct reporters.
  Future<bool> reportCommunityPost({
    required String postId,
    String? reason,
  }) async {
    if (!isEnabled) return false;
    try {
      await _withRetry<void>('report community post', () async {
        await _client!.rpc(
          'report_post',
          params: {'p_post_id': postId, 'p_reason': reason ?? ''},
        );
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud report post failed', e, stackTrace);
      return false;
    }
  }

  /// Deletes the caller's auth identity and data via the delete_account
  /// edge function. Returns null when the function is not deployed so the
  /// caller can fall back to row-level deletion.
  Future<bool?> deleteAccountViaFunction() async {
    if (!isEnabled) return null;
    try {
      final response = await _client!.functions.invoke('delete_account');
      final data = response.data;
      return data is Map && data['ok'] == true;
    } on FunctionException catch (e, stackTrace) {
      if (e.status == 404) return null;
      _logger.error('Account deletion function failed', e, stackTrace);
      return false;
    } catch (e, stackTrace) {
      _logger.error('Account deletion function failed', e, stackTrace);
      return null;
    }
  }

  /// Removes the caller's like. Returns true when a like was removed,
  /// false when no like existed, and null on failure.
  Future<bool?> unlikeCommunityPost({
    required String postId,
    required String userId,
  }) async {
    if (!isEnabled) return null;

    List<dynamic> deleted;
    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return null;

      deleted = await _withRetry<List<dynamic>>(
        'delete community post like',
        () async {
          return _client!
              .from('community_post_likes')
              .delete()
              .eq('post_id', postId)
              .eq('user_id', effectiveUserId)
              .select('post_id');
        },
      );
    } catch (e, stackTrace) {
      _logger.error('Cloud unlike failed', e, stackTrace);
      return null;
    }
    if (deleted.isEmpty) return false;

    try {
      await _withRetry<void>('refresh post like count via rpc', () async {
        await _client!.rpc(
          'refresh_post_like_count',
          params: {'p_post_id': postId},
        );
      });
      return true;
    } catch (e, stackTrace) {
      _logger.warning(
        'Like refresh RPC failed, falling back to direct update',
        e,
        stackTrace,
      );
    }

    // Compatibility fallback for schemas without the refresh RPC.
    try {
      final record = await _withRetry<Map<String, dynamic>?>(
        'fetch post likes for unlike fallback',
        () async {
          return _client!
              .from('community_posts')
              .select('likes')
              .eq('id', postId)
              .maybeSingle();
        },
      );
      if (record == null) return true;
      final currentLikes = (record['likes'] as num?)?.toInt() ?? 0;
      final nextLikes = currentLikes > 0 ? currentLikes - 1 : 0;
      await _withRetry<Map<String, dynamic>?>(
        'decrement post like fallback',
        () async {
          return _client!
              .from('community_posts')
              .update(<String, dynamic>{
                'likes': nextLikes,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', postId)
              .select('id')
              .maybeSingle();
        },
      );
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud unlike fallback failed', e, stackTrace);
      // The like row is already gone; report success so the UI stays
      // consistent with the user's action.
      return true;
    }
  }

  Future<List<Map<String, dynamic>>> getCommunityComments(String postId) async {
    if (!isEnabled) return <Map<String, dynamic>>[];

    try {
      final result = await _withRetry<List<dynamic>>(
        'get community comments',
        () async {
          return _client!
              .from('community_comments')
              .select()
              .eq('post_id', postId)
              .order('created_at', ascending: true);
        },
      );
      return List<Map<String, dynamic>>.from(result);
    } catch (e, stackTrace) {
      _logger.error('Cloud get comments failed', e, stackTrace);
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, int>> getCommunityCommentCounts(
    List<String> postIds,
  ) async {
    if (!isEnabled || postIds.isEmpty) return <String, int>{};

    try {
      final result = await _withRetry<List<dynamic>>(
        'get community comment counts',
        () async {
          return _client!
              .from('community_comments')
              .select('post_id')
              .inFilter('post_id', postIds);
        },
      );

      final counts = <String, int>{};
      for (final row in result) {
        final postId = row['post_id']?.toString() ?? '';
        if (postId.isEmpty) continue;
        counts[postId] = (counts[postId] ?? 0) + 1;
      }
      return counts;
    } catch (e, stackTrace) {
      _logger.error('Cloud get comment counts failed', e, stackTrace);
      return <String, int>{};
    }
  }

  Future<bool> saveCommunityComment({
    required String id,
    required String postId,
    required String userId,
    required String userName,
    required String content,
    String? profileImage,
  }) async {
    if (!isEnabled) return false;

    try {
      final effectiveUserId = _effectiveUserId(userId);
      if (effectiveUserId == null) return false;

      await _withRetry<void>('save community comment', () async {
        await _client!.from('community_comments').upsert(<String, dynamic>{
          'id': id,
          'post_id': postId,
          'user_id': effectiveUserId,
          'user_name': userName,
          'profile_image': profileImage,
          'content': content,
        }, onConflict: 'id');
      });
      return true;
    } catch (e, stackTrace) {
      _logger.error('Cloud save comment failed', e, stackTrace);
      return false;
    }
  }
}
