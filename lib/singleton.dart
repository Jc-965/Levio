import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:parkiwell/services/app_logger.dart';
import 'package:parkiwell/services/cloud_backend_service.dart';
import 'package:parkiwell/services/content_filter.dart';
import 'package:parkiwell/services/encrypted_cache_store.dart';
import 'package:parkiwell/services/encrypted_mutation_journal_store.dart';
import 'package:parkiwell/services/health_sync_coordinator.dart';
import 'package:parkiwell/services/longitudinal_analytics.dart';
import 'package:parkiwell/services/medication_reminder_service.dart';
import 'package:parkiwell/services/offline_sync_engine.dart';
import 'package:parkiwell/services/secure_session_storage.dart';
import 'package:parkiwell/utils/log_timestamp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'theme/app_theme.dart';

/// Main application state manager
///
/// Singleton pattern for centralized state management with:
/// - Cloud database persistence
/// - Secure data handling
/// - Comprehensive logging
class Singleton extends ChangeNotifier {
  static final Singleton _instance = Singleton._internal();
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  final CloudBackendService _cloud = CloudBackendService();
  final ContentModerationService _moderation = ContentModerationService();
  final EncryptedCacheStore _cacheStore = EncryptedCacheStore();
  final AppLogger _logger = AppLogger();
  final Uuid _uuid = const Uuid();
  final Connectivity _connectivity = Connectivity();
  final HealthSyncCoordinator _healthSyncCoordinator =
      const HealthSyncCoordinator();
  final LongitudinalAnalytics _longitudinalAnalytics =
      const LongitudinalAnalytics();
  late final OfflineSyncEngine _offlineSyncEngine;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  static const String _localCacheKey = 'parkiwell_local_cache_v1';
  static const String _communityCacheKey = 'parkiwell_community_cache_v1';
  static const String _syncStatusKey = 'parkiwell_last_sync_status_v1';
  static const String _syncTimestampKey = 'parkiwell_last_sync_time_v1';

  factory Singleton() => _instance;

  void notifyListenersSafe() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      notifyListeners();
    });
    // A post-frame callback only fires if a frame is produced; on an idle
    // screen (e.g. connectivity restored while nothing animates) the
    // notification would otherwise be deferred indefinitely.
    binding.ensureVisualUpdate();
  }

  Singleton._internal() {
    _offlineSyncEngine = OfflineSyncEngine(
      EncryptedMutationJournalStore(
        SharedPreferencesMutationJournalStore(_prefs),
        _cacheStore,
      ),
    );
  }

  // App state
  bool _initialized = false;
  bool _isOnline = true;
  ConnectivityResult _connectionType = ConnectivityResult.none;
  bool _isSyncInProgress = false;
  DateTime? _lastSyncAt;
  String _lastSyncStatus = 'Not synced yet';
  bool _hasHydratedLocalCache = false;
  bool firstTime = true;
  int page = 0;
  List<List<String>> log = [];
  List<List<String>> schedule = [];
  final List<Map<String, dynamic>> medicationEvents = [];
  LongitudinalAnalyticsResult? _analyticsCache;
  int _healthDataVersion = 0;
  int _lastMutationMicros = 0;

  // Speech therapy exercises for Parkinson's (official YouTube channels)
  Map<String, List<String>> speeches = {
    "0ndTdBnVwFY": [
      "LSVT LOUD Introduction",
      "Official LSVT LOUD introduction from LSVT Global focused on safe voice amplitude training for Parkinson's.",
      "9:55",
      "Source: LSVTGLOBAL (YouTube)",
    ],
    "fJXCDDZJLDg": [
      "Introduction to LSVT LOUD",
      "Official LSVT LOUD overview session introducing core daily voice exercises and cueing strategies.",
      "",
      "Source: LSVTGLOBAL (YouTube)",
    ],
    "dzKy4vKp5_I": [
      "Voice Exercises with Rachel",
      "Guided vocal warmups and speech-strength practice for Parkinson's led by a clinical voice specialist.",
      "25:00",
      "Source: Power for Parkinsons (YouTube)",
    ],
    "0TKUdR5Nisk": [
      "Beatles Sing Along",
      "Singing-based speech session to practice loud, clear voice projection with rhythm and articulation drills.",
      "45:00",
      "Source: Power for Parkinsons (YouTube)",
    ],
    "zO5KQb4mUFA": [
      "Speaking with INTENT",
      "Professional education session covering speaking intent, swallow safety, and communication strategies in Parkinson's care.",
      "53:00",
      "Source: UT Southwestern Medical Center (YouTube)",
    ],
    "RmWOwGvyVZI": [
      "LSVT BIG & LOUD Combined",
      "Complete LSVT program combining voice (LOUD) and movement (BIG) exercises for comprehensive therapy.",
      "15:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "L8bkqvf6TRs": [
      "LSVT LOUD Vocal Therapy",
      "Parkinson's Foundation vocal session focused on loudness, breath support, and speech clarity.",
      "22:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "kGZYg19rYCU": [
      "SPEAK OUT! Program Overview",
      "Official Parkinson Voice Project overview of the SPEAK OUT! method for intentional speech.",
      "8:00",
      "Source: Parkinson Voice Project (YouTube)",
    ],
    "O0k_3tsrVYA": [
      "SPEAK OUT! Lesson 4",
      "Guided Parkinson speech practice session from Parkinson Voice Project's official lesson series.",
      "30:00",
      "Source: Parkinson Voice Project (YouTube)",
    ],
    "BNZ3XrGc-aw": [
      "Let's Talk Speech: Part 1",
      "APDA educational session on common speech changes in Parkinson's and practical communication strategies.",
      "35:00",
      "Source: APDA (YouTube)",
    ],
    "WjQRwn8SFZk": [
      "Speech & Swallowing in PD",
      "APDA expert discussion on speech and swallowing care with concrete therapy guidance.",
      "58:00",
      "Source: APDA (YouTube)",
    ],
  };

  // Physical therapy exercises from official Parkinson-focused sources
  Map<String, List<String>> exercises = {
    "QbWyxn8XE-I": [
      "Exercise Essentials: Intro",
      "Davis Phinney Foundation introduction to why exercise is essential in Parkinson's care.",
      "10:00",
      "Source: Davis Phinney Foundation (YouTube)",
    ],
    "AZV3_NfcpVs": [
      "Sit 'n' Fit Workout",
      "Chair-based aerobic routine designed for safe daily movement and endurance.",
      "14:05",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "HHtgtNmBivo": [
      "Chair Workout for Balance",
      "Power for Parkinson's chair workout to improve gait, balance, cognition, and mobility.",
      "35:00",
      "Source: Power for Parkinsons (YouTube)",
    ],
    "4wB43bbSdm8": [
      "Seated Workout",
      "Seated movement routine focused on coordination and brain-body activation.",
      "12:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "No2EIvShhP0": [
      "Reach Your Peak Chair Class",
      "Parkinson's UK chair workout with mobility and coordination drills.",
      "30:00",
      "Source: Parkinson's UK (YouTube)",
    ],
    "RfI_v-HQb5I": [
      "Managing Symptoms Exercises",
      "Seated exercises designed to safely support symptom management at home.",
      "20:00",
      "Source: Power for Parkinsons (YouTube)",
    ],
    "G5OvzAORfuc": [
      "PWR!Moves + Aerobic",
      "Parkinson's Foundation moderate-to-high intensity class for stamina, gait, and movement amplitude.",
      "33:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "4qAbME5b7y0": [
      "PWR!Moves Flow",
      "Official Parkinson's Foundation flow session emphasizing posture, transitions, and full-body control.",
      "20:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "jyOk-2DmVnU": [
      "Move to Improve",
      "Strength and balance training with seated-to-standing progressions from Parkinson's Foundation.",
      "37:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "eFhjqxZ5UkY": [
      "PWR Moves Class",
      "All-level Parkinson's movement class focused on range of motion, agility, and coordination.",
      "44:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "AG4prHkdCjY": [
      "Fitness Friday: PWR! Moves",
      "Foundation-led home routine for safe daily activity and confidence in movement.",
      "24:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "zIFtb-R24Ec": [
      "Strong & Steady",
      "Official Parkinson's Foundation class centered on stability, controlled movement, and fall-risk reduction.",
      "20:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
    "pgtGOgVIhqc": [
      "LSVT BIG Movements",
      "Parkinson's Foundation session introducing LSVT BIG movement principles for larger, clearer motions.",
      "24:00",
      "Source: Parkinson's Foundation (YouTube)",
    ],
  };

  String currentURL = "";
  static final RegExp _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  String name = "[Name]";
  String email = "[Email]";
  int age = 0;
  String image = "images/711128.png";
  int postNum = 0;
  int exerNum = 0;
  int weeklySpeechExerciseGoal = 4;
  int weeklyPhysicalExerciseGoal = 4;
  final List<Map<String, dynamic>> recoverySessions = <Map<String, dynamic>>[];

  // ID tracking
  List<String> logIDs = [];
  List<String> scheduleIDs = [];

  // Community cache
  final List<Map<String, dynamic>> communityPosts = [];
  final Map<String, List<Map<String, dynamic>>> communityComments = {};
  String? _lastCommunityError;
  String? _lastCommunitySupportMessage;

  /// Initialize singleton services
  Future<void> initialize({bool isProduction = false}) async {
    if (_initialized) return;

    _logger.init(isProduction: isProduction);
    await _offlineSyncEngine.initialize();
    for (final mutation in _offlineSyncEngine.pendingMutations) {
      _observeMutationTimestamp(mutation.clientUpdatedAt);
    }
    await _readSyncMetadata();
    await _hydrateFromLocalCache();
    _applyPendingMutationsToLocalState();
    if (_offlineSyncEngine.pendingCount > 0) {
      await _persistLocalCache();
    }
    await _initializeConnectivityMonitoring();
    await _cloud.initialize();
    if (_cloud.isEnabled) {
      await _replayPendingMutations();
      if (_offlineSyncEngine.pendingCount == 0) {
        await _markSyncSuccess('Cloud connected');
      } else {
        await _markSyncPending(
          '${_offlineSyncEngine.pendingCount} changes pending',
        );
      }
    } else if (_hasHydratedLocalCache) {
      await _markSyncPending('Cloud unavailable - using local cache');
    } else {
      await _markSyncFailure('Cloud unavailable');
    }
    _initialized = true;
    _logger.info('Singleton initialized');
  }

  void setFirstTime(bool b) {
    firstTime = b;
    _persistLocalCache();
    notifyListenersSafe();
  }

  Future<void> setUID(String uid) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString('userID', uid);
  }

  Future<String?> getUID() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getString('userID');
  }

  Future<void> setTheme(bool t) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setBool('theme', t);
  }

  Future<bool> getTheme() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getBool('theme') ?? false;
  }

  Future<void> setSound(double s) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setDouble('sound', s);
  }

  Future<double> getSound() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getDouble('sound') ?? 1.0;
  }

  void setPage(int n) {
    // Navigation state only: not worth re-serializing the whole health
    // snapshot. The page still rides along with the next real persist.
    page = n;
    notifyListenersSafe();
  }

  void setName(String n) {
    name = n;
    _persistLocalCache();
    notifyListenersSafe();
  }

  void setImage(String i) {
    image = i;
    _persistLocalCache();
    notifyListenersSafe();
  }

  void setEmail(String e) {
    email = e;
    _persistLocalCache();
    notifyListenersSafe();
  }

  static const String recoveryTypePhysical = 'physical';
  static const String recoveryTypeSpeech = 'speech';

  int get totalRecoverySessions => recoverySessions.length;
  int get totalPhysicalExerciseSessions =>
      recoverySessionsForType(recoveryTypePhysical);
  int get totalSpeechExerciseSessions =>
      recoverySessionsForType(recoveryTypeSpeech);
  int get weeklyPhysicalExerciseSessions => recoverySessionsForType(
    recoveryTypePhysical,
    from: _startOfWeek(DateTime.now()),
  );
  int get weeklySpeechExerciseSessions => recoverySessionsForType(
    recoveryTypeSpeech,
    from: _startOfWeek(DateTime.now()),
  );

  double get recoveryProgress {
    final totalGoal = weeklyPhysicalExerciseGoal + weeklySpeechExerciseGoal;
    if (totalGoal == 0) return 0;
    final completed =
        weeklyPhysicalExerciseSessions + weeklySpeechExerciseSessions;
    return (completed / totalGoal).clamp(0, 1).toDouble();
  }

  double get weeklyPhysicalGoalProgress {
    if (weeklyPhysicalExerciseGoal == 0) return 0;
    return (weeklyPhysicalExerciseSessions / weeklyPhysicalExerciseGoal)
        .clamp(0, 1)
        .toDouble();
  }

  double get weeklySpeechGoalProgress {
    if (weeklySpeechExerciseGoal == 0) return 0;
    return (weeklySpeechExerciseSessions / weeklySpeechExerciseGoal)
        .clamp(0, 1)
        .toDouble();
  }

  DateTime _startOfWeek(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return local.subtract(Duration(days: local.weekday - DateTime.monday));
  }

  DateTime? _parseRecoverySessionDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String? _normalizeRecoveryType(String? type) {
    final normalized = type?.trim().toLowerCase();
    if (normalized == recoveryTypeSpeech) return recoveryTypeSpeech;
    if (normalized == recoveryTypePhysical ||
        normalized == 'exercise' ||
        normalized == 'physical_exercise') {
      return recoveryTypePhysical;
    }
    return null;
  }

  Map<String, dynamic>? _normalizedRecoverySession(Map entry) {
    final type = _normalizeRecoveryType(entry['type']?.toString());
    final rawVideoId = (entry['video_id'] ?? entry['videoId'] ?? '')
        .toString()
        .trim();
    // Motion coach sessions live in their own id namespace and must survive
    // cache reloads, mutation replays, and cloud restores; only YouTube-style
    // ids go through YouTube normalization.
    final videoId =
        rawVideoId.length > motionSessionIdPrefix.length &&
            rawVideoId.startsWith(motionSessionIdPrefix)
        ? rawVideoId
        : normalizeYouTubeVideoId(rawVideoId);
    final completedAt =
        _parseRecoverySessionDate(entry['completed_at']) ?? DateTime.now();

    if (type == null || videoId == null) return null;

    return <String, dynamic>{
      'id': (entry['id']?.toString().trim().isNotEmpty == true)
          ? entry['id'].toString()
          : _uuid.v4(),
      'type': type,
      'video_id': videoId,
      'title':
          entry['title']?.toString() ??
          (type == recoveryTypeSpeech
              ? speeches[videoId]?.first
              : exercises[videoId]?.first) ??
          '',
      'completed_at': completedAt.toIso8601String(),
    };
  }

  void _addLegacyRecoverySession(String type, String videoId) {
    final normalized = normalizeYouTubeVideoId(videoId);
    if (normalized == null) return;
    final title = type == recoveryTypeSpeech
        ? speeches[normalized]?.first ?? 'Speech exercise'
        : exercises[normalized]?.first ?? 'Physical exercise';
    recoverySessions.add(<String, dynamic>{
      'id': _uuid.v4(),
      'type': type,
      'video_id': normalized,
      'title': title,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }

  void setTherapyGoals({
    required int weeklySpeech,
    required int weeklyPhysical,
  }) {
    weeklySpeechExerciseGoal = weeklySpeech.clamp(0, 99).toInt();
    weeklyPhysicalExerciseGoal = weeklyPhysical.clamp(0, 99).toInt();
    _invalidateAnalytics();
    _persistLocalCache();
    notifyListenersSafe();
  }

  Future<int> recordPhysicalExerciseSession(
    String videoId, {
    DateTime? completedAt,
  }) {
    return _recordRecoverySession(
      recoveryTypePhysical,
      videoId,
      completedAt: completedAt,
    );
  }

  /// Identifier prefix for camera-coached motion sessions stored in the
  /// shared recovery log. They are not YouTube videos, so their ids live in
  /// a distinct namespace while still counting as physical sessions for the
  /// weekly plan, history, and cloud sync (the backend accepts any text id).
  static const String motionSessionIdPrefix = 'motion:';

  /// Log a completed motion coach session as a physical recovery session.
  ///
  /// Only the fact of completion, the routine identity, and the time are
  /// recorded here; scores and per-movement evidence stay in the coach's
  /// local-only history.
  Future<void> recordMotionCoachSession({
    required String routineId,
    required String title,
    DateTime? completedAt,
  }) async {
    final trimmedRoutineId = routineId.trim();
    final trimmedTitle = title.trim();
    if (trimmedRoutineId.isEmpty || trimmedTitle.isEmpty) {
      _logger.warning('Dropped motion session with blank identity');
      return;
    }

    final completionTime = (completedAt ?? DateTime.now()).toLocal();
    if (completionTime.isAfter(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      _logger.warning(
        'Dropped motion session with future completion time $completionTime',
      );
      return;
    }

    final session = <String, dynamic>{
      'id': _uuid.v4(),
      'type': recoveryTypePhysical,
      'video_id': '$motionSessionIdPrefix$trimmedRoutineId',
      'title': trimmedTitle,
      'completed_at': completionTime.toIso8601String(),
    };
    recoverySessions.add(session);
    exerNum = totalRecoverySessions;
    _invalidateAnalytics();
    notifyListenersSafe();

    try {
      await _queueHealthMutation(
        entityType: SyncEntityType.recoverySession,
        entityId: session['id']!.toString(),
        operation: SyncMutationOperation.upsert,
        payload: session,
      );
      await _persistLocalCache();
      unawaited(syncPendingMutations());
    } catch (error) {
      recoverySessions.removeWhere(
        (entry) => entry['id']?.toString() == session['id']?.toString(),
      );
      exerNum = totalRecoverySessions;
      _invalidateAnalytics();
      notifyListenersSafe();
      rethrow;
    }
  }

  Future<int> recordSpeechExerciseSession(
    String videoId, {
    DateTime? completedAt,
  }) {
    return _recordRecoverySession(
      recoveryTypeSpeech,
      videoId,
      completedAt: completedAt,
    );
  }

  Future<int> _recordRecoverySession(
    String type,
    String videoId, {
    DateTime? completedAt,
  }) async {
    final normalized = normalizeYouTubeVideoId(videoId);
    if (normalized == null) return 0;

    final completionTime = (completedAt ?? DateTime.now()).toLocal();
    if (completionTime.isAfter(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      return 0;
    }

    final title = type == recoveryTypeSpeech
        ? speeches[normalized]?.first ?? 'Speech exercise'
        : exercises[normalized]?.first ?? 'Physical exercise';
    final session = <String, dynamic>{
      'id': _uuid.v4(),
      'type': type,
      'video_id': normalized,
      'title': title,
      'completed_at': completionTime.toIso8601String(),
    };
    recoverySessions.add(session);
    exerNum = totalRecoverySessions;
    _invalidateAnalytics();
    notifyListenersSafe();

    try {
      await _queueHealthMutation(
        entityType: SyncEntityType.recoverySession,
        entityId: session['id']!.toString(),
        operation: SyncMutationOperation.upsert,
        payload: session,
      );
      await _persistLocalCache();
      unawaited(syncPendingMutations());
      return recoverySessionCountForVideo(type, normalized);
    } catch (error) {
      recoverySessions.removeWhere(
        (entry) => entry['id']?.toString() == session['id']?.toString(),
      );
      exerNum = totalRecoverySessions;
      _invalidateAnalytics();
      notifyListenersSafe();
      rethrow;
    }
  }

  Future<bool> deleteRecoverySessionById(String id) async {
    final trimmedId = id.trim();
    if (trimmedId.isEmpty) return false;

    final index = recoverySessions.indexWhere(
      (session) => session['id']?.toString() == trimmedId,
    );
    if (index == -1) return false;

    await _queueHealthMutation(
      entityType: SyncEntityType.recoverySession,
      entityId: trimmedId,
      operation: SyncMutationOperation.delete,
    );
    recoverySessions.removeAt(index);
    exerNum = totalRecoverySessions;
    _invalidateAnalytics();
    await _persistLocalCache();
    unawaited(syncPendingMutations());
    notifyListenersSafe();
    return true;
  }

  int recoverySessionsForType(String type, {DateTime? from, DateTime? to}) {
    final normalizedType = _normalizeRecoveryType(type);
    if (normalizedType == null) return 0;
    return recoverySessions.where((session) {
      if (session['type'] != normalizedType) return false;
      final completedAt = _parseRecoverySessionDate(session['completed_at']);
      if (completedAt == null) return false;
      if (from != null && completedAt.isBefore(from)) return false;
      if (to != null && !completedAt.isBefore(to)) return false;
      return true;
    }).length;
  }

  int recoverySessionCountForVideo(String type, String videoId) {
    final normalizedType = _normalizeRecoveryType(type);
    final normalizedVideoId = normalizeYouTubeVideoId(videoId);
    if (normalizedType == null || normalizedVideoId == null) return 0;
    return recoverySessions.where((session) {
      return session['type'] == normalizedType &&
          session['video_id'] == normalizedVideoId;
    }).length;
  }

  int exerciseSessionCountForVideo(String videoId) {
    return recoverySessionCountForVideo(recoveryTypePhysical, videoId);
  }

  int speechSessionCountForVideo(String videoId) {
    return recoverySessionCountForVideo(recoveryTypeSpeech, videoId);
  }

  List<String> recommendedPhysicalExerciseIds({int limit = 2}) {
    final ids = exercises.keys.toList();
    ids.sort((a, b) {
      final countCompare = exerciseSessionCountForVideo(
        a,
      ).compareTo(exerciseSessionCountForVideo(b));
      if (countCompare != 0) return countCompare;
      return exercises[a]!.first.compareTo(exercises[b]!.first);
    });
    return ids.take(limit).toList();
  }

  List<String> recommendedSpeechExerciseIds({int limit = 1}) {
    final ids = speeches.keys.toList();
    ids.sort((a, b) {
      final countCompare = speechSessionCountForVideo(
        a,
      ).compareTo(speechSessionCountForVideo(b));
      if (countCompare != 0) return countCompare;
      return speeches[a]!.first.compareTo(speeches[b]!.first);
    });
    return ids.take(limit).toList();
  }

  Map<String, String> monthMap = {
    'January': "01",
    'February': "02",
    'March': "03",
    'April': "04",
    'May': "05",
    'June': "06",
    'July': "07",
    'August': "08",
    'September': "09",
    'October': "10",
    'November': "11",
    'December': "12",
  };

  DateTime? _parseLogTimestamp(String value) => parseLogTimestamp(value);

  void sortTime({bool descending = true}) {
    if (log.length <= 1) return;

    try {
      // Parse each timestamp once up front; the comparator otherwise
      // re-parses strings O(n log n) times per sort.
      final parsed = List<DateTime?>.generate(
        log.length,
        (i) => _parseLogTimestamp(log[i][0]),
        growable: false,
      );
      final order = List<int>.generate(log.length, (i) => i);
      order.sort((a, b) {
        final dateA = parsed[a];
        final dateB = parsed[b];

        if (dateA == null && dateB == null) return a.compareTo(b);
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return descending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });

      sortLog(order);
    } catch (e) {
      _logger.error('Error sorting time', e);
    }

    notifyListenersSafe();
  }

  void sortLog(List<int> order) {
    final oldLogs = List<List<String>>.from(
      log.map((entry) => List<String>.from(entry)),
    );
    final oldLogIds = List<String>.from(logIDs);

    final sortedLogs = <List<String>>[];
    final sortedLogIds = <String>[];

    for (final index in order) {
      if (index < 0 || index >= oldLogs.length) continue;
      sortedLogs.add(oldLogs[index]);
      sortedLogIds.add(index < oldLogIds.length ? oldLogIds[index] : '');
    }

    log
      ..clear()
      ..addAll(sortedLogs);
    logIDs
      ..clear()
      ..addAll(sortedLogIds);
  }

  List<String> month = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  Map<String, double> medsPerDay = {
    'Monday': 0,
    'Tuesday': 0,
    'Wednesday': 0,
    'Thursday': 0,
    'Friday': 0,
    'Saturday': 0,
    'Sunday': 0,
  };

  Set<String> medicationNames = {};
  double barY = 1;

  void calcBarY() {
    List<double> values = medsPerDay.values.toList();
    values.sort();
    barY = values.isNotEmpty ? values.last + 1 : 1;
  }

  void calcMeds() {
    // Reset before calculating
    medsPerDay = {
      'Monday': 0,
      'Tuesday': 0,
      'Wednesday': 0,
      'Thursday': 0,
      'Friday': 0,
      'Saturday': 0,
      'Sunday': 0,
    };
    medicationNames.clear();

    for (final entry in schedule) {
      if (entry.length < 3) continue;
      if (!medicationNames.contains(entry[0])) {
        medicationNames.add(entry[0]);
      }
      // Every schedule row counts, even a second row for the same drug
      // (morning and evening Levodopa are separate entries), and a row
      // with per-dose times contributes one dose per time.
      final doseCount = entry.length > 3 && entry[3].trim().isNotEmpty
          ? entry[3].split(',').where((t) => t.trim().isNotEmpty).length
          : 1;
      for (final key in medsPerDay.keys) {
        if (entry[2] == 'Everyday' || entry[2].contains(key)) {
          medsPerDay[key] = (medsPerDay[key] ?? 0) + doseCount;
        }
      }
    }
    calcBarY();
  }

  // Theme management
  int colorMode = 0;

  /// False until the user explicitly picks a theme; the app follows the OS
  /// light/dark setting in the meantime, which matters for the light
  /// sensitivity common in this population.
  bool hasExplicitTheme = false;

  void switchColorTheme(bool isDark) {
    hasExplicitTheme = true;
    colorMode = isDark ? 1 : 0;
    setTheme(isDark);
    notifyListenersSafe();
  }

  AppColors get currentColors {
    return colorMode == 1 ? AppTheme.darkColors : AppTheme.lightColors;
  }

  bool get isCloudConnected => _cloud.isEnabled;

  /// True only under a real signed-in account (not the anonymous
  /// bootstrap session). Community features require this.
  bool get hasFullAccount => _cloud.hasFullAccount;
  bool get isCloudConfigured => _cloud.isConfigured;
  String? get lastCloudError => _cloud.lastInitializationError;
  String get backendStatusDescription => _cloud.statusDescription;
  String? get cloudSessionUserId => _cloud.cloudUserId;
  bool get isOnline => _isOnline;
  bool get isSyncInProgress => _isSyncInProgress;
  DateTime? get lastSyncAt => _lastSyncAt;
  String get lastSyncStatus => _lastSyncStatus;
  bool get hasCachedData =>
      _hasHydratedLocalCache ||
      log.isNotEmpty ||
      schedule.isNotEmpty ||
      name != '[Name]';

  String get lastSyncDisplay {
    if (_lastSyncAt == null) return 'Never';
    final local = _lastSyncAt!.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  String get connectivityLabel {
    if (_connectionType == ConnectivityResult.wifi) return 'Wi-Fi';
    if (_connectionType == ConnectivityResult.mobile) return 'Cellular';
    if (_connectionType == ConnectivityResult.ethernet) return 'Ethernet';
    if (_connectionType == ConnectivityResult.vpn) return 'VPN';
    if (_connectionType == ConnectivityResult.bluetooth) return 'Bluetooth';
    if (_connectionType == ConnectivityResult.none) return 'Offline';
    return 'Network';
  }

  String? consumeLastCommunityError() {
    final error = _lastCommunityError;
    _lastCommunityError = null;
    return error;
  }

  String? consumeLastCommunitySupportMessage() {
    final message = _lastCommunitySupportMessage;
    _lastCommunitySupportMessage = null;
    return message;
  }

  void _applyConnectivityResults(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    final primaryResult = results.isNotEmpty
        ? results.first
        : ConnectivityResult.none;
    if (_isOnline == hasConnection && _connectionType == primaryResult) return;
    final wasOnline = _isOnline;
    _isOnline = hasConnection;
    _connectionType = primaryResult;
    if (!wasOnline && hasConnection && _initialized && _cloud.isEnabled) {
      unawaited(syncPendingMutations());
    }
    notifyListenersSafe();
  }

  Future<void> _initializeConnectivityMonitoring() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _applyConnectivityResults(initial);
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _applyConnectivityResults,
      );
    } catch (e, stackTrace) {
      _logger.warning(
        'Unable to initialize connectivity monitoring',
        e,
        stackTrace,
      );
    }
  }

  Future<void> _readSyncMetadata() async {
    final prefs = await _prefs;
    final syncIso = prefs.getString(_syncTimestampKey);
    if (syncIso != null && syncIso.isNotEmpty) {
      _lastSyncAt = DateTime.tryParse(syncIso);
    }
    _lastSyncStatus =
        prefs.getString(_syncStatusKey) ??
        (_lastSyncAt == null ? 'Not synced yet' : 'Synced');
  }

  Future<void> _writeSyncMetadata() async {
    final prefs = await _prefs;
    if (_lastSyncAt != null) {
      await prefs.setString(_syncTimestampKey, _lastSyncAt!.toIso8601String());
    } else {
      await prefs.remove(_syncTimestampKey);
    }
    await prefs.setString(_syncStatusKey, _lastSyncStatus);
  }

  Future<void> _markSyncSuccess(String message) async {
    _lastSyncAt = DateTime.now();
    _lastSyncStatus = message;
    await _writeSyncMetadata();
  }

  Future<void> _markSyncFailure(String message) async {
    _lastSyncStatus = message;
    await _writeSyncMetadata();
  }

  Future<void> _markSyncPending(String message) async {
    _lastSyncStatus = message;
    await _writeSyncMetadata();
  }

  String? normalizeYouTubeVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Already a video ID
    if (_youtubeIdPattern.hasMatch(trimmed)) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    String? candidate;

    if (host.contains('youtu.be')) {
      final path = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      candidate = path.trim();
    } else if (host.contains('youtube.com') ||
        host.contains('youtube-nocookie.com')) {
      candidate = uri.queryParameters['v']?.trim();
      if (candidate == null || candidate.isEmpty) {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          if (segments.first == 'embed' && segments.length > 1) {
            candidate = segments[1].trim();
          } else if (segments.first == 'shorts' && segments.length > 1) {
            candidate = segments[1].trim();
          }
        }
      }
    }

    if (candidate == null || !_youtubeIdPattern.hasMatch(candidate)) {
      return null;
    }
    return candidate;
  }

  void setCurrentUrl(String? url) {
    final normalized = normalizeYouTubeVideoId(url ?? '');
    final next = normalized ?? '';
    if (next == currentURL) return;
    currentURL = next;
    notifyListenersSafe();
  }

  // ==================== Cloud Data Operations ====================

  Future<String?> _resolveUserId() async {
    final storedUid = await getUID();
    final cloudUid = _cloud.cloudUserId;
    final resolvedUid = cloudUid ?? storedUid;

    if (resolvedUid != null && storedUid != resolvedUid) {
      await setUID(resolvedUid);
    }

    return resolvedUid;
  }

  Map<String, dynamic> _decodeDataField(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Keep empty map when persisted payload is malformed.
      }
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _buildLocalCacheSnapshot() {
    return <String, dynamic>{
      'version': 1,
      'cached_at': DateTime.now().toIso8601String(),
      'profile': <String, dynamic>{
        'name': name,
        'email': email,
        'age': age,
        'image': image,
        'post_num': postNum,
        'exer_num': exerNum,
        'first_time': firstTime,
        'page': page,
      },
      'recovery_progress': <String, dynamic>{
        'weekly_speech_goal': weeklySpeechExerciseGoal,
        'weekly_physical_goal': weeklyPhysicalExerciseGoal,
        'sessions': recoverySessions
            .map((session) => Map<String, dynamic>.from(session))
            .toList(),
      },
      'logs': List<Map<String, dynamic>>.generate(
        log.length,
        (index) => <String, dynamic>{
          'id': index < logIDs.length ? logIDs[index] : '',
          'time': log[index].isNotEmpty ? log[index][0] : '',
          'symptom': log[index].length > 1 ? log[index][1] : '',
          'severity': log[index].length > 2 ? log[index][2] : '',
        },
      ),
      'schedules': List<Map<String, dynamic>>.generate(
        schedule.length,
        (index) => <String, dynamic>{
          'id': index < scheduleIDs.length ? scheduleIDs[index] : '',
          'name': schedule[index].isNotEmpty ? schedule[index][0] : '',
          'details': schedule[index].length > 1 ? schedule[index][1] : '',
          'days': schedule[index].length > 2 ? schedule[index][2] : '',
          'times': schedule[index].length > 3 ? schedule[index][3] : '',
        },
      ),
      'medication_events': medicationEvents
          .map((event) => Map<String, dynamic>.from(event))
          .toList(),
    };
  }

  /// Community content is cached under its own key so a symptom edit never
  /// pays to re-serialize and re-encrypt the whole feed.
  Map<String, dynamic> _buildCommunityCacheSnapshot() {
    return <String, dynamic>{
      'community_posts': List<Map<String, dynamic>>.from(
        communityPosts.map((post) => Map<String, dynamic>.from(post)),
      ),
      'community_comments': communityComments.map(
        (postId, comments) => MapEntry(
          postId,
          List<Map<String, dynamic>>.from(
            comments.map((comment) => Map<String, dynamic>.from(comment)),
          ),
        ),
      ),
    };
  }

  Future<void> _persistCommunityCache() async {
    try {
      final prefs = await _prefs;
      final sealed = await _cacheStore.seal(
        jsonEncode(_buildCommunityCacheSnapshot()),
      );
      await prefs.setString(_communityCacheKey, sealed);
    } catch (e, stackTrace) {
      _logger.warning('Unable to persist community cache', e, stackTrace);
    }
  }

  Future<void> _hydrateCommunityCache() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_communityCacheKey);
      if (raw == null || raw.isEmpty) return;
      final opened = await _cacheStore.open(raw);
      if (opened == null) return;
      final decoded = jsonDecode(opened);
      if (decoded is! Map<String, dynamic>) return;
      _applyCommunitySnapshot(decoded);
    } catch (e, stackTrace) {
      _logger.warning('Unable to hydrate community cache', e, stackTrace);
    }
  }

  void _applyLocalCacheSnapshot(Map<String, dynamic> snapshot) {
    final profile = snapshot['profile'];
    if (profile is Map) {
      final profileMap = Map<String, dynamic>.from(profile);
      name = profileMap['name']?.toString() ?? '[Name]';
      email = profileMap['email']?.toString() ?? '[Email]';
      age = (profileMap['age'] as num?)?.toInt() ?? 0;
      image = _effectiveProfileImage(profileMap['image']?.toString());
      postNum = (profileMap['post_num'] as num?)?.toInt() ?? postNum;
      exerNum = (profileMap['exer_num'] as num?)?.toInt() ?? exerNum;
      firstTime = profileMap['first_time'] as bool? ?? firstTime;
      page = (profileMap['page'] as num?)?.toInt() ?? page;
    }

    final recoveryProgress = snapshot['recovery_progress'];
    if (recoveryProgress is Map) {
      final progressMap = Map<String, dynamic>.from(recoveryProgress);
      weeklySpeechExerciseGoal =
          (progressMap['weekly_speech_goal'] as num?)?.toInt() ??
          weeklySpeechExerciseGoal;
      weeklyPhysicalExerciseGoal =
          (progressMap['weekly_physical_goal'] as num?)?.toInt() ??
          weeklyPhysicalExerciseGoal;

      recoverySessions.clear();
      final sessions = progressMap['sessions'];
      if (sessions is List) {
        recoverySessions.addAll(
          sessions
              .whereType<Map>()
              .map(_normalizedRecoverySession)
              .whereType<Map<String, dynamic>>(),
        );
      } else {
        for (final id
            in progressMap['completed_exercise_video_ids'] as List<dynamic>? ??
                const <dynamic>[]) {
          _addLegacyRecoverySession(recoveryTypePhysical, id.toString());
        }
        for (final id
            in progressMap['completed_speech_video_ids'] as List<dynamic>? ??
                const <dynamic>[]) {
          _addLegacyRecoverySession(recoveryTypeSpeech, id.toString());
        }
      }
      exerNum = totalRecoverySessions;
    }

    log
      ..clear()
      ..addAll(
        (snapshot['logs'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((entry) {
              final map = Map<String, dynamic>.from(entry);
              return <String>[
                map['time']?.toString() ?? '',
                map['symptom']?.toString() ?? '',
                map['severity']?.toString() ?? '',
              ];
            }),
      );

    logIDs
      ..clear()
      ..addAll(
        (snapshot['logs'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (entry) =>
                  Map<String, dynamic>.from(entry)['id']?.toString() ?? '',
            ),
      );

    schedule
      ..clear()
      ..addAll(
        (snapshot['schedules'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((entry) {
              final map = Map<String, dynamic>.from(entry);
              final times = map['times']?.toString() ?? '';
              return <String>[
                map['name']?.toString() ?? '',
                map['details']?.toString() ?? '',
                map['days']?.toString() ?? '',
                if (times.isNotEmpty) times,
              ];
            }),
      );

    scheduleIDs
      ..clear()
      ..addAll(
        (snapshot['schedules'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (entry) =>
                  Map<String, dynamic>.from(entry)['id']?.toString() ?? '',
            ),
      );

    medicationEvents
      ..clear()
      ..addAll(
        (snapshot['medication_events'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((event) => Map<String, dynamic>.from(event)),
      );

    // Legacy snapshots carried community content inline; newer builds
    // store it under its own key.
    if (snapshot.containsKey('community_posts')) {
      _applyCommunitySnapshot(snapshot);
    }

    calcMeds();
    _invalidateAnalytics();
  }

  void _applyCommunitySnapshot(Map<String, dynamic> snapshot) {
    communityPosts
      ..clear()
      ..addAll(
        (snapshot['community_posts'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((post) => Map<String, dynamic>.from(post)),
      );

    communityComments.clear();
    final comments = snapshot['community_comments'];
    if (comments is Map) {
      comments.forEach((key, value) {
        final postId = key.toString();
        final rawThread = value is List ? value : const <dynamic>[];
        final thread = rawThread
            .whereType<Map>()
            .map((comment) => Map<String, dynamic>.from(comment))
            .toList();
        communityComments[postId] = thread;
      });
    }

    _recalculateOwnPostCount();
  }

  /// Slots dropped from the last reminder sync because the plan exceeded
  /// the platform pending-notification cap. Non-zero means the user's
  /// furthest-out doses have no reminder and the UI should say so.
  int droppedReminderSlots = 0;

  Future<void> _syncMedicationReminders() async {
    final dropped = await MedicationReminderService().syncFromSchedule(
      schedule,
    );
    if (dropped != droppedReminderSlots) {
      droppedReminderSlots = dropped;
      notifyListenersSafe();
    }
  }

  /// Profile "Posts" stat: counts only the signed-in user's posts in the
  /// fetched feed, never the feed size. When identity is unknown (offline
  /// cold start) the persisted value is kept rather than overwritten.
  void _recalculateOwnPostCount() {
    final uid = _cloud.cloudUserId;
    if (uid == null) return;
    postNum = communityPosts
        .where((post) => post['user_id']?.toString() == uid)
        .length;
  }

  Future<void> _hydrateFromLocalCache() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_localCacheKey);
      if (raw == null || raw.isEmpty) return;
      final wasPlaintext = !raw.startsWith(EncryptedCacheStore.payloadPrefix);
      final opened = await _cacheStore.open(raw);
      if (opened == null) return;
      final decoded = jsonDecode(opened);
      if (decoded is! Map<String, dynamic>) return;
      _applyLocalCacheSnapshot(decoded);
      await _hydrateCommunityCache();
      _hasHydratedLocalCache = true;
      _logger.info('Local cache hydrated');
      if (wasPlaintext && !_cacheStore.keystoreUnavailable) {
        // Migrate a legacy plaintext snapshot to sealed storage.
        await _persistLocalCache();
      }
      notifyListenersSafe();
    } catch (e, stackTrace) {
      _logger.warning('Unable to hydrate local cache', e, stackTrace);
    }
  }

  Future<void> _persistTail = Future<void>.value();

  /// Serializes snapshot writes: each request runs after the previous write
  /// finishes, so overlapping full-state serializations can never race or
  /// land out of order. A wedged predecessor (for example a stalled keystore
  /// call) is abandoned after a short grace period rather than blocking all
  /// future persistence. [_writeLocalCacheSnapshot] never throws, keeping
  /// the chain unbroken.
  Future<void> _persistLocalCache() {
    final next = _persistTail
        .timeout(const Duration(seconds: 5), onTimeout: () {})
        .then((_) => _writeLocalCacheSnapshot());
    _persistTail = next;
    return next;
  }

  /// True when the last local-cache write failed, meaning changes made in
  /// this session survive only in memory. Surfaced as a warning banner so a
  /// wedged keystore is never a silent data loss.
  bool localPersistenceFailed = false;

  int _persistGeneration = 0;

  Future<void> _writeLocalCacheSnapshot() async {
    // The persist tail abandons a wedged predecessor after a timeout but
    // cannot cancel it; the generation stamp keeps that late writer from
    // clobbering a newer snapshot when it finally completes.
    final generation = ++_persistGeneration;
    try {
      final prefs = await _prefs;
      final snapshot = _buildLocalCacheSnapshot();
      final sealed = await _cacheStore.seal(jsonEncode(snapshot));
      if (generation != _persistGeneration) return;
      await prefs.setString(_localCacheKey, sealed);
      if (localPersistenceFailed) {
        localPersistenceFailed = false;
        notifyListenersSafe();
      }
    } catch (e, stackTrace) {
      _logger.warning('Unable to persist local cache', e, stackTrace);
      if (!localPersistenceFailed) {
        localPersistenceFailed = true;
        notifyListenersSafe();
      }
    }
  }

  int get pendingMutationCount => _offlineSyncEngine.pendingCount;
  int get healthDataVersion => _healthDataVersion;

  LongitudinalAnalyticsResult get longitudinalInsights {
    return _analyticsCache ??= _longitudinalAnalytics.analyze(
      symptoms: _symptomObservations(),
      medicationEvents: _medicationAdherenceEvents(),
      therapySessions: _therapyObservations(),
      weeklyTherapyGoal: weeklySpeechExerciseGoal + weeklyPhysicalExerciseGoal,
      expectedDosesByWeekday: _expectedDosesByWeekday(),
    );
  }

  /// Expected doses per weekday from the medication schedule, so adherence
  /// compares taken doses to the plan instead of to itself.
  Map<int, int> _expectedDosesByWeekday() {
    const dayNumbers = <String, int>{
      'Monday': DateTime.monday,
      'Tuesday': DateTime.tuesday,
      'Wednesday': DateTime.wednesday,
      'Thursday': DateTime.thursday,
      'Friday': DateTime.friday,
      'Saturday': DateTime.saturday,
      'Sunday': DateTime.sunday,
    };
    return <int, int>{
      for (final entry in medsPerDay.entries)
        if (dayNumbers.containsKey(entry.key))
          dayNumbers[entry.key]!: entry.value.round(),
    };
  }

  void _invalidateAnalytics() {
    _analyticsCache = null;
    _healthDataVersion += 1;
  }

  Iterable<SymptomObservation> _symptomObservations() sync* {
    for (final entry in log) {
      if (entry.length < 3) continue;
      final occurredAt = _parseLogTimestamp(entry[0]);
      if (occurredAt == null) continue;
      yield SymptomObservation(
        occurredAt: occurredAt,
        severity: _severityScore(entry[2]),
        symptom: entry[1],
      );
    }
  }

  Iterable<MedicationAdherenceEvent> _medicationAdherenceEvents() sync* {
    for (final event in medicationEvents) {
      final scheduledAt = DateTime.tryParse(
        event['scheduled_at']?.toString() ?? '',
      );
      if (scheduledAt == null) continue;
      final takenAt = DateTime.tryParse(event['taken_at']?.toString() ?? '');
      yield MedicationAdherenceEvent(
        medicationName: event['medication_name']?.toString() ?? 'Medication',
        scheduledAt: scheduledAt,
        takenAt: event['status'] == 'taken' ? takenAt : null,
      );
    }
  }

  Iterable<TherapyObservation> _therapyObservations() sync* {
    for (final session in recoverySessions) {
      final completedAt = _parseRecoverySessionDate(session['completed_at']);
      if (completedAt == null) continue;
      yield TherapyObservation(
        completedAt: completedAt,
        therapyType: session['type']?.toString() ?? 'therapy',
      );
    }
  }

  double _severityScore(String severity) {
    switch (severity.trim().toLowerCase()) {
      case 'very mild':
        return 1;
      case 'mild':
        return 2;
      case 'moderate':
        return 3;
      case 'severe':
        return 4;
      case 'very severe':
        return 5;
      default:
        return double.tryParse(severity) ?? 0;
    }
  }

  DateTime _nextMutationTimestamp() {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    _lastMutationMicros = max(nowMicros, _lastMutationMicros + 1);
    return DateTime.fromMicrosecondsSinceEpoch(
      _lastMutationMicros,
      isUtc: true,
    );
  }

  void _observeMutationTimestamp(DateTime timestamp) {
    _lastMutationMicros = max(
      _lastMutationMicros,
      timestamp.toUtc().microsecondsSinceEpoch,
    );
  }

  void _observeCloudVersions(Iterable<Map<String, dynamic>> records) {
    for (final record in records) {
      final timestamp = DateTime.tryParse(
        record['client_updated_at']?.toString() ?? '',
      );
      if (timestamp != null) _observeMutationTimestamp(timestamp);
    }
  }

  Future<void> _queueHealthMutation({
    required SyncEntityType entityType,
    required String entityId,
    required SyncMutationOperation operation,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    await _offlineSyncEngine.enqueue(
      mutationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      clientUpdatedAt: _nextMutationTimestamp(),
    );
  }

  Future<int> _replayPendingMutations() async {
    // Health mutations stay queued locally until a real account exists;
    // replaying them under the anonymous bootstrap session would upload
    // unconsented health data to an unrecoverable identity.
    if (!_cloud.hasFullAccount) return 0;
    if (!_cloud.isEnabled || _offlineSyncEngine.pendingCount == 0) return 0;

    final uid = await _resolveUserId();
    if (uid == null || !await _ensureCloudUserRecord(uid)) {
      await _markSyncPending(
        '${_offlineSyncEngine.pendingCount} changes pending',
      );
      return 0;
    }

    final acknowledged = await _offlineSyncEngine.replay(
      (mutations) => _cloud.applyHealthMutations(
        mutations.map((mutation) => mutation.toRpcJson()).toList(),
      ),
    );
    if (_offlineSyncEngine.pendingCount == 0) {
      await _markSyncSuccess('All changes synced');
    } else {
      await _markSyncPending(
        '${_offlineSyncEngine.pendingCount} changes pending',
      );
    }
    return acknowledged;
  }

  Future<bool> syncPendingMutations() async {
    if (_offlineSyncEngine.pendingCount == 0) return true;
    if (!_cloud.isEnabled) {
      await _markSyncPending(
        '${_offlineSyncEngine.pendingCount} changes pending',
      );
      return false;
    }

    await _replayPendingMutations();
    notifyListenersSafe();
    return _offlineSyncEngine.pendingCount == 0;
  }

  void _applyPendingMutationsToLocalState() {
    for (final mutation in _offlineSyncEngine.pendingMutations) {
      switch (mutation.entityType) {
        case SyncEntityType.log:
          _applyPendingLogMutation(mutation);
        case SyncEntityType.schedule:
          _applyPendingScheduleMutation(mutation);
        case SyncEntityType.recoverySession:
          _applyPendingRecoveryMutation(mutation);
        case SyncEntityType.medicationEvent:
          _applyPendingMedicationMutation(mutation);
      }
    }

    if (log.length > 1) {
      final order = List<int>.generate(log.length, (index) => index)
        ..sort((a, b) {
          final dateA = _parseLogTimestamp(log[a][0]);
          final dateB = _parseLogTimestamp(log[b][0]);
          if (dateA == null && dateB == null) return a.compareTo(b);
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA);
        });
      sortLog(order);
    }
    exerNum = totalRecoverySessions;
    calcMeds();
    _invalidateAnalytics();
  }

  void _applyPendingLogMutation(SyncMutation mutation) {
    final index = logIDs.indexOf(mutation.entityId);
    if (mutation.operation == SyncMutationOperation.delete) {
      if (index >= 0) {
        log.removeAt(index);
        logIDs.removeAt(index);
      }
      return;
    }

    final entry = <String>[
      mutation.payload['time']?.toString() ?? '',
      mutation.payload['symptom']?.toString() ?? '',
      mutation.payload['severity']?.toString() ?? '',
    ];
    if (index >= 0) {
      log[index] = entry;
    } else {
      log.add(entry);
      logIDs.add(mutation.entityId);
    }
  }

  void _applyPendingScheduleMutation(SyncMutation mutation) {
    final index = scheduleIDs.indexOf(mutation.entityId);
    if (mutation.operation == SyncMutationOperation.delete) {
      if (index >= 0) {
        schedule.removeAt(index);
        scheduleIDs.removeAt(index);
      }
      return;
    }

    final mutationTimes = mutation.payload['times']?.toString() ?? '';
    final entry = <String>[
      mutation.payload['name']?.toString() ?? '',
      mutation.payload['details']?.toString() ?? '',
      mutation.payload['days']?.toString() ?? '',
      if (mutationTimes.isNotEmpty) mutationTimes,
    ];
    if (index >= 0) {
      schedule[index] = entry;
    } else {
      schedule.add(entry);
      scheduleIDs.add(mutation.entityId);
    }
  }

  void _applyPendingRecoveryMutation(SyncMutation mutation) {
    final index = recoverySessions.indexWhere(
      (session) => session['id']?.toString() == mutation.entityId,
    );
    if (mutation.operation == SyncMutationOperation.delete) {
      if (index >= 0) recoverySessions.removeAt(index);
      return;
    }

    final normalized = _normalizedRecoverySession(<String, dynamic>{
      ...mutation.payload,
      'id': mutation.entityId,
    });
    if (normalized == null) return;
    if (index >= 0) {
      recoverySessions[index] = normalized;
    } else {
      recoverySessions.add(normalized);
    }
  }

  void _applyPendingMedicationMutation(SyncMutation mutation) {
    final index = medicationEvents.indexWhere(
      (event) => event['id']?.toString() == mutation.entityId,
    );
    if (mutation.operation == SyncMutationOperation.delete) {
      if (index >= 0) medicationEvents.removeAt(index);
      return;
    }

    final event = <String, dynamic>{
      ...mutation.payload,
      'id': mutation.entityId,
      'client_updated_at': mutation.clientUpdatedAt.toIso8601String(),
    };
    if (index >= 0) {
      medicationEvents[index] = event;
    } else {
      medicationEvents.add(event);
    }
  }

  String _normalizedDisplayName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'ParkiWell Member' : trimmed;
  }

  String _effectiveProfileImage(String? candidate) {
    final trimmed = candidate?.trim() ?? '';
    return trimmed.isEmpty ? 'images/711128.png' : trimmed;
  }

  /// Only bundled asset references may be published to shared tables.
  /// Device file paths leak app sandbox identifiers to every reader, break
  /// on other devices, and go stale when the OS purges the picker cache.
  String _cloudSafeProfileImage(String? candidate) {
    final value = _effectiveProfileImage(candidate);
    return value.startsWith('images/') ? value : 'images/711128.png';
  }

  Future<bool> _ensureCloudUserRecord(String uid) async {
    return _cloud.upsertUser(
      id: uid,
      name: _normalizedDisplayName(name == '[Name]' ? '' : name),
      age: age,
      profileImage: _cloudSafeProfileImage(image),
      email: email == '[Email]' ? null : email,
    );
  }

  /// Load user data from cloud backend
  /// True only when the last [loadUser] call reached the cloud and the
  /// profile row was definitively absent. Transient failures leave this
  /// false so boot logic never discards a stored user ID on a flaky call.
  bool profileConfirmedAbsent = false;

  Future<bool> loadUser() async {
    profileConfirmedAbsent = false;
    try {
      if (!_cloud.isEnabled) {
        _logger.warning('Cloud backend is not available for user loading.');
        await _markSyncPending('Cloud unavailable - showing local cache');
        return hasCachedData;
      }

      final uid = await _resolveUserId();
      if (uid == null) {
        _logger.debug('No cloud user ID found');
        return false;
      }

      await _replayPendingMutations();
      final snapshot = await _healthSyncCoordinator.loadParallel(
        user: () => _cloud.getUser(uid),
        logs: () => _cloud.getLogs(uid),
        schedules: () => _cloud.getSchedules(uid),
        recoverySessions: () => _cloud.getRecoverySessions(uid),
        medicationEvents: () => _cloud.getMedicationEvents(uid),
      );
      final userData = snapshot.user;
      if (userData == null) {
        // getUser rethrows on failure, so reaching null here means the
        // query succeeded and the row genuinely does not exist.
        profileConfirmedAbsent = true;
        _logger.debug('User not found in cloud database');
        await _markSyncFailure('Cloud user profile not found');
        return false;
      }

      final userName = userData['name']?.toString().trim() ?? '';
      final userEmail = userData['email']?.toString().trim() ?? '';
      final userImage = userData['profile_image']?.toString().trim() ?? '';

      name = userName.isEmpty ? '[Name]' : userName;
      email = userEmail.isEmpty ? '[Email]' : userEmail;
      age = (userData['age'] as num?)?.toInt() ?? 0;
      final cloudImage = userImage.isEmpty ? 'images/711128.png' : userImage;
      // The cloud row never stores device file paths, so a locally picked
      // photo must survive sync instead of being reset to the default.
      final localIsDevicePhoto =
          image.isNotEmpty && !image.startsWith('images/');
      if (!(cloudImage == 'images/711128.png' && localIsDevicePhoto)) {
        image = cloudImage;
      }

      // The server reserves one community alias per account (identity
      // trigger); adopting it here keeps the member's public identity
      // stable across devices and reinstalls.
      final cloudAlias = userData['community_alias']?.toString().trim() ?? '';
      if (cloudAlias.isNotEmpty) {
        final aliasPrefs = await _prefs;
        await aliasPrefs.setString('community_alias', cloudAlias);
      }

      _observeCloudVersions(snapshot.logs);
      _observeCloudVersions(snapshot.schedules);
      _observeCloudVersions(snapshot.recoverySessions);
      _observeCloudVersions(snapshot.medicationEvents);

      log.clear();
      logIDs.clear();
      for (final logEntry in snapshot.logs) {
        final parsedData = _decodeDataField(logEntry['data']);
        log.add(<String>[
          (logEntry['event_time'] ?? parsedData['time'] ?? '').toString(),
          (logEntry['symptom'] ??
                  parsedData['symptom'] ??
                  logEntry['title'] ??
                  '')
              .toString(),
          (logEntry['severity'] ?? parsedData['severity'] ?? '').toString(),
        ]);
        logIDs.add((logEntry['id'] ?? '').toString());
      }
      sortTime();

      schedule.clear();
      scheduleIDs.clear();
      for (final scheduleEntry in snapshot.schedules) {
        final parsedData = _decodeDataField(scheduleEntry['data']);
        final scheduleTimes = (parsedData['times'] ?? '').toString();
        schedule.add(<String>[
          (parsedData['name'] ?? scheduleEntry['title'] ?? '').toString(),
          (scheduleEntry['details'] ?? parsedData['details'] ?? '').toString(),
          (scheduleEntry['days'] ?? parsedData['days'] ?? '').toString(),
          if (scheduleTimes.isNotEmpty) scheduleTimes,
        ]);
        scheduleIDs.add((scheduleEntry['id'] ?? '').toString());
      }

      recoverySessions
        ..clear()
        ..addAll(
          snapshot.recoverySessions
              .map(_normalizedRecoverySession)
              .whereType<Map<String, dynamic>>(),
        );
      exerNum = totalRecoverySessions;

      medicationEvents
        ..clear()
        ..addAll(
          snapshot.medicationEvents.map(
            (event) => Map<String, dynamic>.from(event),
          ),
        );

      _applyPendingMutationsToLocalState();
      calcMeds();
      _invalidateAnalytics();
      await _persistLocalCache();
      if (_offlineSyncEngine.pendingCount == 0) {
        await _markSyncSuccess('Synced successfully');
      } else {
        await _markSyncPending(
          '${_offlineSyncEngine.pendingCount} changes pending',
        );
      }
      notifyListenersSafe();
      _logger.info('User data loaded from cloud successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error loading user', e, stackTrace);
      await _markSyncFailure('Sync failed - using local cache');
      return false;
    }
  }

  Future<CloudAuthProfile?> signInWithGoogle() async {
    return _cloud.signInWithGoogle();
  }

  Future<CloudAuthProfile?> signInWithApple() async {
    return _cloud.signInWithApple();
  }

  Future<CloudAuthProfile?> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return _cloud.signUpWithEmailPassword(email: email, password: password);
  }

  Future<CloudAuthProfile?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return _cloud.signInWithEmailPassword(email: email, password: password);
  }

  Future<bool?> isCurrentUserEmailVerified() async {
    return _cloud.isCurrentUserEmailVerified();
  }

  Stream<CloudAuthProfile> get cloudVerifiedSignIns => _cloud.verifiedSignIns;
  Stream<void> get passwordRecoveryEvents => _cloud.passwordRecoveryEvents;
  bool get isPasswordRecoveryPending => _cloud.isPasswordRecoveryPending;

  Future<bool> resendEmailVerification(String email) async {
    return _cloud.resendEmailVerification(email);
  }

  Future<bool> requestPasswordReset(String email) async {
    return _cloud.requestPasswordReset(email);
  }

  Future<bool> updatePassword(String password) async {
    return _cloud.updatePassword(password);
  }

  Future<bool> syncNow({bool includeCommunity = true}) async {
    if (_isSyncInProgress) return false;

    _isSyncInProgress = true;
    notifyListenersSafe();

    try {
      if (!_cloud.isEnabled) {
        await _markSyncFailure('Cloud unavailable');
        return false;
      }

      final userLoaded = await loadUser();
      if (!userLoaded) {
        await _markSyncFailure('Sync failed');
        return false;
      }

      if (includeCommunity) {
        await loadCommunityPosts(limit: 100);
      }

      await _persistLocalCache();
      // loadUser may have left mutations queued (for example a replay batch
      // the server rejected); reporting success then would hide unsynced
      // health data behind a green banner.
      if (_offlineSyncEngine.pendingCount > 0) {
        await _markSyncPending(
          '${_offlineSyncEngine.pendingCount} changes pending',
        );
        return false;
      }
      await _markSyncSuccess('Synced successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Manual sync failed', e, stackTrace);
      await _markSyncFailure('Sync failed');
      return false;
    } finally {
      _isSyncInProgress = false;
      notifyListenersSafe();
    }
  }

  String exportBackupJson() {
    final payload = <String, dynamic>{
      'backup_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'sync': <String, dynamic>{
        'last_sync_at': _lastSyncAt?.toIso8601String(),
        'last_sync_status': _lastSyncStatus,
      },
      'snapshot': _buildLocalCacheSnapshot(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<bool> importBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return false;
      final snapshot = decoded['snapshot'];
      if (snapshot is! Map<String, dynamic>) return false;

      _applyLocalCacheSnapshot(snapshot);
      _hasHydratedLocalCache = true;
      await _persistLocalCache();
      await _markSyncPending('Backup restored locally');
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Backup import failed', e, stackTrace);
      return false;
    }
  }

  Future<bool> createOrSyncAuthenticatedUser({
    required String displayName,
    String? userEmail,
    String? profileImage,
    bool preferExistingName = false,
  }) async {
    try {
      if (!_cloud.isEnabled) return false;

      final uid = await _resolveUserId();
      if (uid == null) return false;

      var normalizedName = _normalizedDisplayName(displayName);
      if (preferExistingName) {
        // Sign-in flows only derive a fallback name (email prefix or provider
        // metadata); never let that overwrite the name the user chose.
        final existing = await _cloud.getUser(uid);
        final existingName = existing?['name']?.toString().trim();
        if (existingName != null &&
            existingName.isNotEmpty &&
            existingName != '[Name]') {
          normalizedName = existingName;
        }
      }
      final normalizedEmail = (userEmail != null && userEmail.trim().isNotEmpty)
          ? userEmail.trim()
          : null;
      final normalizedImage = _effectiveProfileImage(profileImage ?? image);

      final prefs = await _prefs;
      await prefs.setString('userID', uid);

      final synced = await _cloud.upsertUser(
        overwrite: true,
        id: uid,
        name: normalizedName,
        age: age,
        profileImage: normalizedImage,
        email: normalizedEmail,
      );
      if (!synced) return false;

      name = normalizedName;
      email = normalizedEmail ?? '[Email]';
      image = normalizedImage;
      firstTime = false;

      await loadUser();
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error syncing authenticated user', e, stackTrace);
      return false;
    }
  }

  /// Create a local-only profile when cloud is not configured (e.g. email signup without backend).
  Future<bool> createLocalOnlyUser({
    required String displayName,
    String? userEmail,
    String? profileImage,
  }) async {
    try {
      final uid = _uuid.v4();
      await setUID(uid);
      name = _normalizedDisplayName(displayName);
      email = (userEmail != null && userEmail.trim().isNotEmpty)
          ? userEmail.trim()
          : '[Email]';
      image = _effectiveProfileImage(profileImage ?? image);
      firstTime = false;
      await _persistLocalCache();
      notifyListenersSafe();
      _logger.info('Local-only user created');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error creating local user', e, stackTrace);
      return false;
    }
  }

  /// Create a new user in cloud database
  Future<bool> createUser(String userName, int age) async {
    try {
      if (!_cloud.isEnabled) return false;

      final uid = await _resolveUserId();
      if (uid == null) return false;

      final normalizedName = _normalizedDisplayName(userName);
      final created = await _cloud.upsertUser(
        overwrite: true,
        id: uid,
        name: normalizedName,
        age: age,
        profileImage: _cloudSafeProfileImage(image),
        email: email == '[Email]' ? null : email,
      );
      if (!created) return false;

      final prefs = await _prefs;
      await prefs.setString('userID', uid);
      name = normalizedName;
      this.age = age;

      await _persistLocalCache();
      await _markSyncSuccess('Profile created');
      notifyListenersSafe();
      _logger.info('User created successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error creating user', e, stackTrace);
      return false;
    }
  }

  /// Update user data in cloud database
  Future<bool> updateUser({
    String? userName,
    int? age,
    String? profileImage,
    String? userEmail,
  }) async {
    try {
      if (!_cloud.isEnabled) return false;

      final uid = await _resolveUserId();
      if (uid == null) return false;

      final nextName = userName != null
          ? _normalizedDisplayName(userName)
          : name;
      final nextEmail = userEmail != null
          ? (userEmail.trim().isEmpty ? '[Email]' : userEmail.trim())
          : email;
      final nextAge = age ?? this.age;
      final nextImage = profileImage != null
          ? _effectiveProfileImage(profileImage)
          : _effectiveProfileImage(image);
      final updated = await _cloud.upsertUser(
        overwrite: true,
        id: uid,
        name: nextName,
        age: nextAge,
        // Device file paths stay local; the cloud row only ever holds
        // bundled asset references.
        profileImage: _cloudSafeProfileImage(nextImage),
        email: nextEmail == '[Email]' ? null : nextEmail,
      );
      if (!updated) return false;

      name = nextName;
      email = nextEmail;
      this.age = nextAge;
      image = nextImage;

      await _persistLocalCache();
      await _markSyncSuccess('Profile updated');
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error updating user', e, stackTrace);
      return false;
    }
  }

  /// Save a new log entry
  Future<bool> saveLog(String time, String symptom, String severity) async {
    try {
      final logId = _uuid.v4();
      final payload = <String, dynamic>{
        'time': time,
        'symptom': symptom,
        'severity': severity,
      };

      await _queueHealthMutation(
        entityType: SyncEntityType.log,
        entityId: logId,
        operation: SyncMutationOperation.upsert,
        payload: payload,
      );

      log.add(<String>[time, symptom, severity]);
      logIDs.add(logId);
      sortTime();
      _invalidateAnalytics();
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error saving log', e, stackTrace);
      return false;
    }
  }

  /// Update an existing log entry
  /// ID-addressed so a background reload or re-sort between the moment the
  /// UI captured the entry and the moment the user confirms can never edit
  /// a different medical record.
  Future<bool> updateLogEntryById(
    String logId,
    String time,
    String symptom,
    String severity,
  ) async {
    try {
      final index = logIDs.indexOf(logId);
      if (index < 0) return false;

      final payload = <String, dynamic>{
        'time': time,
        'symptom': symptom,
        'severity': severity,
      };

      await _queueHealthMutation(
        entityType: SyncEntityType.log,
        entityId: logId,
        operation: SyncMutationOperation.upsert,
        payload: payload,
      );

      log[index] = <String>[time, symptom, severity];
      sortTime();
      _invalidateAnalytics();
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error updating log', e, stackTrace);
      return false;
    }
  }

  /// Delete a log entry by its stable ID (see [updateLogEntryById]).
  Future<bool> deleteLogById(String logId) async {
    try {
      final index = logIDs.indexOf(logId);
      if (index < 0) return false;

      await _queueHealthMutation(
        entityType: SyncEntityType.log,
        entityId: logId,
        operation: SyncMutationOperation.delete,
      );

      log.removeAt(index);
      logIDs.removeAt(index);
      _invalidateAnalytics();
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error deleting log', e, stackTrace);
      return false;
    }
  }

  /// Save a new schedule entry
  Future<bool> saveSchedule(
    String medName,
    String details,
    String days, {
    String doseTimes = '',
  }) async {
    try {
      final scheduleId = _uuid.v4();
      final payload = <String, dynamic>{
        'name': medName,
        'details': details,
        'days': days,
        'times': doseTimes,
      };

      await _queueHealthMutation(
        entityType: SyncEntityType.schedule,
        entityId: scheduleId,
        operation: SyncMutationOperation.upsert,
        payload: payload,
      );

      schedule.add(<String>[
        medName,
        details,
        days,
        if (doseTimes.isNotEmpty) doseTimes,
      ]);
      scheduleIDs.add(scheduleId);
      calcMeds();
      unawaited(_syncMedicationReminders());
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error saving schedule', e, stackTrace);
      return false;
    }
  }

  /// Update an existing schedule entry by its stable ID
  /// (see [updateLogEntryById] for why identity beats position).
  Future<bool> updateScheduleEntryById(
    String scheduleId,
    String medName,
    String details,
    String days, {
    String doseTimes = '',
  }) async {
    try {
      final index = scheduleIDs.indexOf(scheduleId);
      if (index < 0) return false;

      final payload = <String, dynamic>{
        'name': medName,
        'details': details,
        'days': days,
        'times': doseTimes,
      };

      await _queueHealthMutation(
        entityType: SyncEntityType.schedule,
        entityId: scheduleId,
        operation: SyncMutationOperation.upsert,
        payload: payload,
      );

      schedule[index] = <String>[
        medName,
        details,
        days,
        if (doseTimes.isNotEmpty) doseTimes,
      ];
      calcMeds();
      unawaited(_syncMedicationReminders());
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error updating schedule', e, stackTrace);
      return false;
    }
  }

  /// Delete a schedule entry by its stable ID (see [updateLogEntryById]).
  Future<bool> deleteScheduleEntryById(String scheduleId) async {
    try {
      final index = scheduleIDs.indexOf(scheduleId);
      if (index < 0) return false;

      await _queueHealthMutation(
        entityType: SyncEntityType.schedule,
        entityId: scheduleId,
        operation: SyncMutationOperation.delete,
      );

      schedule.removeAt(index);
      scheduleIDs.removeAt(index);
      calcMeds();
      unawaited(_syncMedicationReminders());
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error deleting schedule', e, stackTrace);
      return false;
    }
  }

  Future<bool> recordMedicationTakenById(
    String scheduleId, {
    DateTime? takenAt,
    DateTime? scheduledAt,
  }) async {
    try {
      final scheduleIndex = scheduleIDs.indexOf(scheduleId);
      if (scheduleIndex < 0) return false;
      final now = (takenAt ?? DateTime.now()).toUtc();
      final eventId = _uuid.v4();
      final event = <String, dynamic>{
        'id': eventId,
        'schedule_id': scheduleId,
        'medication_name': schedule[scheduleIndex][0],
        'scheduled_at': (scheduledAt ?? now).toUtc().toIso8601String(),
        'taken_at': now.toIso8601String(),
        'status': 'taken',
      };

      await _queueHealthMutation(
        entityType: SyncEntityType.medicationEvent,
        entityId: eventId,
        operation: SyncMutationOperation.upsert,
        payload: event,
      );
      medicationEvents.add(event);
      _invalidateAnalytics();
      await _persistLocalCache();
      // Local persistence is the durability guarantee (mutation journal);
      // the network replay must not hold the save button hostage on a
      // flaky connection.
      unawaited(syncPendingMutations());
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error recording medication event', e, stackTrace);
      return false;
    }
  }

  int medicationDosesTakenForSchedule(String scheduleId) {
    return medicationEvents.where((event) {
      return event['schedule_id']?.toString() == scheduleId &&
          event['status'] == 'taken';
    }).length;
  }

  /// Delete entire account and all associated data
  /// True when the last account deletion removed data rows but could not
  /// remove the auth sign-in identity (edge function not deployed). The UI
  /// reads this to tell the user the truth about what was deleted.
  bool accountDeletionWasPartial = false;

  /// Removes stored avatar files; prefs.clear() cannot touch the
  /// filesystem, so sign-out and deletion clean these explicitly.
  Future<void> _deleteStoredAvatarFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${directory.path}/avatars');
      if (await avatarDir.exists()) {
        await avatarDir.delete(recursive: true);
      }
    } catch (_) {
      // Filesystem unavailable in this environment.
    }
  }

  Future<bool> deleteAccount() async {
    try {
      final uid = await _resolveUserId();
      if (uid != null) {
        // Prefer the delete_account edge function: it removes the auth
        // identity (email, OAuth linkage) as well as the data rows, which
        // the client cannot do with the publishable key alone.
        final viaFunction = await _cloud.deleteAccountViaFunction();
        switch (viaFunction) {
          case AccountDeletionResult.failed:
            _logger.error('Server-side account deletion failed');
            return false;
          case AccountDeletionResult.unavailable:
            // Function not deployed: fall back to row-level deletion. The
            // auth identity survives in this mode; surface that honestly
            // instead of claiming full deletion.
            _logger.warning(
              'delete_account function unavailable; deleting rows only',
            );
            if (!await _cloud.deleteUser(uid)) {
              _logger.error('Failed to delete user from cloud database');
              return false;
            }
            accountDeletionWasPartial = true;
          case AccountDeletionResult.partial:
            accountDeletionWasPartial = true;
          case AccountDeletionResult.deleted:
            accountDeletionWasPartial = false;
        }
      }

      log.clear();
      logIDs.clear();
      schedule.clear();
      scheduleIDs.clear();
      medicationEvents.clear();
      communityPosts.clear();
      communityComments.clear();
      recoverySessions.clear();
      name = '[Name]';
      email = '[Email]';
      image = 'images/711128.png';
      postNum = 0;
      exerNum = 0;
      weeklySpeechExerciseGoal = 4;
      weeklyPhysicalExerciseGoal = 4;
      firstTime = true;
      age = 0;

      final prefs = await SharedPreferences.getInstance();
      await _offlineSyncEngine.clear();
      await prefs.clear();
      // Rotate away the encryption key so any surviving ciphertext copies
      // are permanently unreadable, and drop the keystore-held auth session
      // for the deleted identity.
      await _cacheStore.destroyKey();
      await SecureSessionStorage().removePersistedSession();
      await MedicationReminderService().cancelAll();
      await _deleteStoredAvatarFiles();
      _lastSyncAt = null;
      _lastSyncStatus = 'Not synced yet';
      _hasHydratedLocalCache = false;
      _invalidateAnalytics();

      notifyListenersSafe();
      _logger.info('Account deleted successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error deleting account', e, stackTrace);
      return false;
    }
  }

  /// Sign out current user while preserving app preferences like theme.
  Future<bool> signOut() async {
    try {
      final cloudSignedOut = await _cloud.signOut();

      log.clear();
      logIDs.clear();
      schedule.clear();
      scheduleIDs.clear();
      medicationEvents.clear();
      communityPosts.clear();
      communityComments.clear();
      recoverySessions.clear();
      name = '[Name]';
      email = '[Email]';
      image = 'images/711128.png';
      postNum = 0;
      exerNum = 0;
      weeklySpeechExerciseGoal = 4;
      weeklyPhysicalExerciseGoal = 4;
      firstTime = true;
      age = 0;
      page = 0;
      _lastCommunityError = null;

      final prefs = await SharedPreferences.getInstance();
      await _offlineSyncEngine.clear();
      await prefs.remove('userID');
      await prefs.remove('community_alias');
      await prefs.remove(_localCacheKey);
      await prefs.remove(_syncStatusKey);
      await prefs.remove(_syncTimestampKey);
      // Health traces beyond the cache: pending reminders would name the
      // signed-out user's medications to the next device user, and the
      // avatar file lives outside prefs entirely.
      await MedicationReminderService().cancelAll();
      await _deleteStoredAvatarFiles();
      _lastSyncAt = null;
      _lastSyncStatus = 'Not synced yet';
      _hasHydratedLocalCache = false;
      _invalidateAnalytics();

      notifyListenersSafe();
      return cloudSignedOut;
    } catch (e, stackTrace) {
      _logger.error('Error signing out', e, stackTrace);
      return false;
    }
  }

  // ==================== Community Operations ====================

  static const String _useRealNameKey = 'community_use_real_name';

  /// Posting in a disease-specific community discloses a diagnosis, so the
  /// display name is a persistent alias unless the user opts in to their
  /// real name.
  Future<String> communityDisplayName() async {
    final prefs = await _prefs;
    final useRealName = prefs.getBool(_useRealNameKey) ?? false;
    if (useRealName && name.trim().isNotEmpty && name != '[Name]') {
      return name.trim();
    }

    final existingAlias = prefs.getString('community_alias');
    if (existingAlias != null && existingAlias.trim().isNotEmpty) {
      return existingAlias;
    }

    // Secure RNG and a 900k space keep aliases practically collision-free,
    // so two members are unlikely to appear under the same name.
    final alias = 'Member-${Random.secure().nextInt(900000) + 100000}';
    await prefs.setString('community_alias', alias);
    return alias;
  }

  Future<bool> getCommunityUseRealName() async {
    final prefs = await _prefs;
    return prefs.getBool(_useRealNameKey) ?? false;
  }

  Future<void> setCommunityUseRealName(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_useRealNameKey, value);
    notifyListenersSafe();
  }

  Future<List<Map<String, dynamic>>> loadCommunityPosts({
    int limit = 50,
  }) async {
    try {
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        await _markSyncPending('Cloud unavailable - showing local cache');
        return communityPosts;
      }

      final cloudPosts = await _cloud.getCommunityPosts(limit: limit);
      final uid = await _resolveUserId();
      final postIds = cloudPosts
          .map((post) => post['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      Set<String> likedPostIds = <String>{};
      Map<String, int> commentCounts = <String, int>{};

      if (postIds.isNotEmpty) {
        final metadata = await Future.wait<dynamic>(<Future<dynamic>>[
          uid == null
              ? Future<Set<String>>.value(<String>{})
              : _cloud.getLikedPostIds(userId: uid, postIds: postIds),
          _cloud.getCommunityCommentCounts(postIds),
        ]);
        likedPostIds = Set<String>.from(metadata[0] as Set);
        commentCounts = Map<String, int>.from(metadata[1] as Map);
      }

      final normalizedPosts = cloudPosts.map((post) {
        final copy = Map<String, dynamic>.from(post);
        final postId = copy['id']?.toString() ?? '';
        copy['liked_by_me'] = likedPostIds.contains(postId);
        copy['comment_count'] = commentCounts[postId] ?? 0;
        return copy;
      }).toList();

      communityPosts
        ..clear()
        ..addAll(normalizedPosts);
      _recalculateOwnPostCount();
      await _persistCommunityCache();
      notifyListenersSafe();
      return communityPosts;
    } catch (e, stackTrace) {
      _logger.error('Error loading community posts', e, stackTrace);
      return communityPosts;
    }
  }

  Future<bool> createCommunityPost({
    required String content,
    String? category,
  }) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }

      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }

      if (!await _ensureCloudUserRecord(uid)) {
        _lastCommunityError = 'Unable to verify your profile.';
        return false;
      }

      if (!await _underPostRateLimit()) {
        _lastCommunityError =
            'You are posting quite often. Please wait a while and try again.';
        return false;
      }

      final moderation = _moderation.moderateContent(
        content,
        allowLinks: false,
        userId: uid,
      );
      if (moderation.crisisDetected) {
        _lastCommunitySupportMessage = moderation.supportMessage;
      }
      if (!moderation.isApproved) {
        _lastCommunityError =
            moderation.rejectionReason ??
            'Post does not meet community safety guidelines.';
        return false;
      }

      final safeContent = (moderation.sanitizedContent ?? content).trim();
      if (safeContent.isEmpty) {
        _lastCommunityError = 'Post cannot be empty.';
        return false;
      }

      final postId = _uuid.v4();
      final displayName = await communityDisplayName();
      final createdAt = DateTime.now().toIso8601String();

      final saved = await _cloud.saveCommunityPost(
        id: postId,
        userId: uid,
        userName: displayName,
        content: safeContent,
        category: category,
        profileImage: _cloudSafeProfileImage(image),
      );
      if (!saved) {
        _lastCommunityError = 'Unable to share post right now.';
        return false;
      }
      await _recordPostForRateLimit();

      communityPosts.insert(0, <String, dynamic>{
        'id': postId,
        'user_id': uid,
        'user_name': displayName,
        'profile_image': _cloudSafeProfileImage(image),
        'content': safeContent,
        'category': category,
        'likes': 0,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      _recalculateOwnPostCount();
      await _persistCommunityCache();
      await _markSyncSuccess('Community post synced');
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error creating community post', e, stackTrace);
      _lastCommunityError = 'Unable to share post right now.';
      return false;
    }
  }

  Future<bool> updateCommunityPost({
    required String postId,
    required String content,
    String? category,
  }) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }

      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }

      final moderation = _moderation.moderateContent(
        content,
        allowLinks: false,
        userId: uid,
      );
      if (moderation.crisisDetected) {
        _lastCommunitySupportMessage = moderation.supportMessage;
      }
      if (!moderation.isApproved) {
        _lastCommunityError =
            moderation.rejectionReason ??
            'Post does not meet community safety guidelines.';
        return false;
      }

      final safeContent = (moderation.sanitizedContent ?? content).trim();
      if (safeContent.isEmpty) {
        _lastCommunityError = 'Post cannot be empty.';
        return false;
      }

      final updated = await _cloud.updateCommunityPost(
        postId: postId,
        content: safeContent,
        category: category,
      );
      if (!updated) {
        _lastCommunityError = 'Unable to update post right now.';
        return false;
      }

      final index = communityPosts.indexWhere((post) => post['id'] == postId);
      if (index != -1) {
        communityPosts[index]['content'] = safeContent;
        communityPosts[index]['category'] = category;
        communityPosts[index]['updated_at'] = DateTime.now().toIso8601String();
      }

      await _persistCommunityCache();
      await _markSyncSuccess('Community post update synced');
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error updating community post', e, stackTrace);
      _lastCommunityError = 'Unable to update post right now.';
      return false;
    }
  }

  Future<bool> deleteCommunityPost(String postId) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }

      final deleted = await _cloud.deleteCommunityPost(postId);
      if (!deleted) {
        _lastCommunityError = 'Unable to delete post right now.';
        return false;
      }

      communityPosts.removeWhere((post) => post['id'] == postId);
      communityComments.remove(postId);
      _recalculateOwnPostCount();
      await _persistCommunityCache();
      await _markSyncSuccess('Community post deletion synced');
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error deleting community post', e, stackTrace);
      _lastCommunityError = 'Unable to delete post right now.';
      return false;
    }
  }

  Future<bool> likeCommunityPost(String postId) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }

      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }

      if (!await _ensureCloudUserRecord(uid)) {
        _lastCommunityError = 'Unable to verify your profile.';
        return false;
      }

      final likeResult = await _cloud.likeCommunityPost(
        postId: postId,
        userId: uid,
      );
      if (likeResult == null) {
        _lastCommunityError = 'Unable to like post right now.';
        return false;
      }
      // likeResult false means the like already existed; treat as success
      // so a tremor-induced double tap is never punished with an error.

      final idx = communityPosts.indexWhere((p) => p['id'] == postId);
      if (idx != -1) {
        final likes = (communityPosts[idx]['likes'] as num?)?.toInt() ?? 0;
        if (likeResult) communityPosts[idx]['likes'] = likes + 1;
        communityPosts[idx]['liked_by_me'] = true;
      }
      await _persistCommunityCache();
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error liking post', e, stackTrace);
      _lastCommunityError = 'Unable to like post right now.';
      return false;
    }
  }

  static const String _postTimesKey = 'community_post_times_v1';

  /// Local posting rate limit backing [ContentModerationService.maxPostsPerHour].
  /// Server-side enforcement is still an open item; this at least keeps a
  /// well-behaved client honest.
  Future<List<DateTime>> _recentPostTimes() async {
    final prefs = await _prefs;
    final now = DateTime.now();
    return (prefs.getStringList(_postTimesKey) ?? const <String>[])
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .where((t) => now.difference(t) < const Duration(hours: 1))
        .toList();
  }

  Future<bool> _underPostRateLimit() async {
    final recent = await _recentPostTimes();
    return recent.length < ContentModerationService.maxPostsPerHour;
  }

  /// Recorded only after a post actually saves, so failed or moderated
  /// attempts never consume the hourly quota.
  Future<void> _recordPostForRateLimit() async {
    final prefs = await _prefs;
    final recent = await _recentPostTimes()
      ..add(DateTime.now());
    await prefs.setStringList(
      _postTimesKey,
      recent.map((t) => t.toIso8601String()).toList(),
    );
  }

  static const String _blockedUsersKey = 'community_blocked_users_v1';
  Set<String>? _blockedUserIds;

  bool _blockedUsersSynced = false;

  Future<Set<String>> blockedUserIds() async {
    final prefs = await _prefs;
    _blockedUserIds ??=
        (prefs.getStringList(_blockedUsersKey) ?? const <String>[]).toSet();
    // The server list is authoritative once per session: replacing (not
    // unioning) means an unblock made on another device actually takes
    // effect here. On fetch failure the local set is kept untouched.
    if (!_blockedUsersSynced && _cloud.isEnabled) {
      final uid = await _resolveUserId();
      if (uid != null) {
        final remote = await _cloud.getBlockedUserIds(uid);
        if (remote != null) {
          _blockedUsersSynced = true;
          _blockedUserIds = {...remote};
          await prefs.setStringList(
            _blockedUsersKey,
            _blockedUserIds!.toList(),
          );
        }
      }
    }
    return _blockedUserIds!;
  }

  /// Blocks hide the member locally and are stored server-side so they
  /// follow the account across devices.
  Future<void> blockCommunityUser(String userId) async {
    final blocked = await blockedUserIds();
    if (userId.trim().isEmpty || !blocked.add(userId)) return;
    final prefs = await _prefs;
    await prefs.setStringList(_blockedUsersKey, blocked.toList());
    final uid = await _resolveUserId();
    if (uid != null) {
      unawaited(
        _cloud.setUserBlock(blockerId: uid, blockedId: userId, blocked: true),
      );
    }
    notifyListenersSafe();
  }

  Future<void> unblockCommunityUser(String userId) async {
    final blocked = await blockedUserIds();
    if (!blocked.remove(userId)) return;
    final prefs = await _prefs;
    await prefs.setStringList(_blockedUsersKey, blocked.toList());
    final uid = await _resolveUserId();
    if (uid != null) {
      unawaited(
        _cloud.setUserBlock(blockerId: uid, blockedId: userId, blocked: false),
      );
    }
    notifyListenersSafe();
  }

  Future<bool> reportCommunityPost(String postId, {String? reason}) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }
      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }
      final reported = await _cloud.reportCommunityPost(
        postId: postId,
        reason: reason,
      );
      if (!reported) {
        _lastCommunityError = 'Unable to report post right now.';
      }
      return reported;
    } catch (e, stackTrace) {
      _logger.error('Error reporting post', e, stackTrace);
      _lastCommunityError = 'Unable to report post right now.';
      return false;
    }
  }

  Future<bool> reportCommunityComment(
    String commentId, {
    String? reason,
  }) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }
      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }
      final reported = await _cloud.reportCommunityComment(
        commentId: commentId,
        reason: reason,
      );
      if (!reported) {
        _lastCommunityError = 'Unable to report comment right now.';
      }
      return reported;
    } catch (e, stackTrace) {
      _logger.error('Error reporting comment', e, stackTrace);
      _lastCommunityError = 'Unable to report comment right now.';
      return false;
    }
  }

  Future<bool> unlikeCommunityPost(String postId) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }

      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }

      final result = await _cloud.unlikeCommunityPost(
        postId: postId,
        userId: uid,
      );
      if (result == null) {
        _lastCommunityError = 'Unable to update like right now.';
        return false;
      }

      final idx = communityPosts.indexWhere((p) => p['id'] == postId);
      if (idx != -1) {
        final likes = (communityPosts[idx]['likes'] as num?)?.toInt() ?? 0;
        if (result && likes > 0) communityPosts[idx]['likes'] = likes - 1;
        communityPosts[idx]['liked_by_me'] = false;
      }
      await _persistCommunityCache();
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error unliking post', e, stackTrace);
      _lastCommunityError = 'Unable to update like right now.';
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> loadCommunityComments(
    String postId,
  ) async {
    try {
      if (!_cloud.isEnabled) {
        return communityComments[postId] ?? <Map<String, dynamic>>[];
      }

      final cloudComments = await _cloud.getCommunityComments(postId);
      communityComments[postId] = cloudComments;
      await _persistCommunityCache();
      notifyListenersSafe();
      return cloudComments;
    } catch (e, stackTrace) {
      _logger.error('Error loading comments', e, stackTrace);
      return communityComments[postId] ?? <Map<String, dynamic>>[];
    }
  }

  Future<bool> createCommunityComment({
    required String postId,
    required String content,
  }) async {
    try {
      _lastCommunityError = null;
      if (!_cloud.isEnabled) {
        _lastCommunityError = 'Cloud sync unavailable.';
        return false;
      }

      final uid = await _resolveUserId();
      if (uid == null) {
        _lastCommunityError = 'Complete profile setup first.';
        return false;
      }

      if (!await _ensureCloudUserRecord(uid)) {
        _lastCommunityError = 'Unable to verify your profile.';
        return false;
      }

      final moderation = _moderation.moderateContent(
        content,
        allowLinks: false,
        userId: uid,
      );
      if (moderation.crisisDetected) {
        _lastCommunitySupportMessage = moderation.supportMessage;
      }
      if (!moderation.isApproved) {
        _lastCommunityError =
            moderation.rejectionReason ??
            'Comment does not meet community safety guidelines.';
        return false;
      }

      final safeContent = (moderation.sanitizedContent ?? content).trim();
      if (safeContent.isEmpty) {
        _lastCommunityError = 'Comment cannot be empty.';
        return false;
      }

      final commentId = _uuid.v4();
      final displayName = await communityDisplayName();
      final createdAt = DateTime.now().toIso8601String();

      final saved = await _cloud.saveCommunityComment(
        id: commentId,
        postId: postId,
        userId: uid,
        userName: displayName,
        content: safeContent,
        profileImage: _cloudSafeProfileImage(image),
      );
      if (!saved) {
        _lastCommunityError = 'Unable to add comment right now.';
        return false;
      }

      final cache = communityComments.putIfAbsent(
        postId,
        () => <Map<String, dynamic>>[],
      );
      cache.add(<String, dynamic>{
        'id': commentId,
        'post_id': postId,
        'user_id': uid,
        'user_name': displayName,
        'profile_image': _cloudSafeProfileImage(image),
        'content': safeContent,
        'created_at': createdAt,
      });

      final postIdx = communityPosts.indexWhere((post) => post['id'] == postId);
      if (postIdx != -1) {
        final current =
            (communityPosts[postIdx]['comment_count'] as num?)?.toInt() ?? 0;
        communityPosts[postIdx]['comment_count'] = current + 1;
      }

      await _persistCommunityCache();
      await _markSyncSuccess('Community comment synced');
      notifyListenersSafe();
      return true;
    } catch (e, stackTrace) {
      _logger.error('Error creating comment', e, stackTrace);
      _lastCommunityError = 'Unable to add comment right now.';
      return false;
    }
  }

  // Legacy method for compatibility

  /// Get in-memory cache statistics for debugging

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
