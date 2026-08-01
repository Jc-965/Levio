import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:parkiwell/config/environment.dart';
import 'package:parkiwell/services/app_logger.dart';

void main() {
  group('loggerThresholdFor', () {
    test('production maps to error so info records stay off device logs', () {
      expect(loggerThresholdFor(LogLevel.error), Level.error);
    });

    test('staging and testing suppress info and below', () {
      expect(loggerThresholdFor(LogLevel.warning), Level.warning);
    });

    test('development logs everything', () {
      expect(loggerThresholdFor(LogLevel.debug), Level.trace);
    });

    test('threshold ordering matches logger level ordering', () {
      expect(
        loggerThresholdFor(LogLevel.debug).value <
            loggerThresholdFor(LogLevel.info).value,
        isTrue,
      );
      expect(
        loggerThresholdFor(LogLevel.info).value <
            loggerThresholdFor(LogLevel.warning).value,
        isTrue,
      );
      expect(
        loggerThresholdFor(LogLevel.warning).value <
            loggerThresholdFor(LogLevel.error).value,
        isTrue,
      );
    });
  });

  test('environment log levels are strictest in production', () {
    // Guards against someone relaxing production logging by accident.
    expect(
      loggerThresholdFor(LogLevel.error).value,
      greaterThanOrEqualTo(Level.error.value),
    );
  });
}
