import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../config/environment.dart';

/// Production-grade logging service
///
/// Provides structured logging with different levels for debugging,
/// monitoring, and error tracking in production environments.
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  late final Logger _logger;
  bool _isProduction = false;

  AppLogger._internal() {
    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      filter: _EnvironmentLogFilter(),
    );
  }

  /// Initialize logger with production mode setting
  void init({bool isProduction = false}) {
    _isProduction = isProduction;
  }

  /// Log debug information (not shown in production)
  void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    if (!_isProduction) {
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log general information
  void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warnings
  void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: _releaseSafe(error), stackTrace: stackTrace);
  }

  /// Redacts exception payloads in release: PostgrestException and friends
  /// can embed row data, which must never reach device logs.
  Object? _releaseSafe(dynamic error) {
    if (error == null) return null;
    return kReleaseMode ? error.runtimeType.toString() : error;
  }

  /// Log errors
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: _releaseSafe(error), stackTrace: stackTrace);
  }

  /// Log fatal errors
  void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: _releaseSafe(error), stackTrace: stackTrace);
  }

  /// Log database operations
  void database(String operation, {String? table, String? details}) {
    debug('DB [$operation] ${table ?? ''}: ${details ?? ''}');
  }

  /// Log security events
  void security(String event, {Map<String, dynamic>? metadata}) {
    info('SECURITY [$event] ${metadata?.toString() ?? ''}');
  }

  /// Log content moderation events
  void moderation(String action, {String? reason, String? contentPreview}) {
    info('MODERATION [$action] Reason: ${reason ?? 'N/A'}');
  }
}

/// Maps the app's environment [LogLevel] to the logger package's [Level].
Level loggerThresholdFor(LogLevel level) {
  switch (level) {
    case LogLevel.debug:
      return Level.trace;
    case LogLevel.info:
      return Level.info;
    case LogLevel.warning:
      return Level.warning;
    case LogLevel.error:
      return Level.error;
  }
}

/// Filters log output by the environment's configured level, so release
/// builds never print info-level records (which can reference user activity)
/// to device logs. Release mode enforces a warning floor even when the
/// build forgot to pass ENVIRONMENT, so a misconfigured release can never
/// log user activity.
class _EnvironmentLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    var threshold = loggerThresholdFor(EnvironmentConfig.logLevel);
    if (kReleaseMode && threshold.value < Level.warning.value) {
      threshold = Level.warning;
    }
    return event.level.value >= threshold.value;
  }
}
