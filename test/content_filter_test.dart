import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/content_filter.dart';

void main() {
  final moderation = ContentModerationService();

  group('Crisis language support', () {
    test('crisis disclosure is approved, not blocked', () {
      final result = moderation.moderateContent(
        'Lately I have been thinking about suicide and I feel alone.',
      );

      expect(result.isApproved, isTrue);
      expect(result.crisisDetected, isTrue);
      expect(result.supportMessage, ContentModerationService.crisisMessage);
      expect(result.rejectionReason, isNull);
    });

    test('crisis disclosure is never censored', () {
      final result = moderation.moderateContent(
        'Some days I want to die and I do not know who to tell.',
      );

      expect(result.isApproved, isTrue);
      expect(result.sanitizedContent, contains('want to die'));
      expect(result.sanitizedContent, isNot(contains('*')));
    });

    test('crisis disclosure is not labeled harassment or profanity', () {
      final result = moderation.moderateContent(
        'I have thoughts of self harm when my symptoms get bad.',
      );

      final types = result.violations.map((v) => v.type).toList();
      expect(types, contains(ViolationType.crisisSupport));
      expect(types, isNot(contains(ViolationType.harassment)));
      expect(types, isNot(contains(ViolationType.profanity)));
    });

    test('detects common crisis phrasings', () {
      const phrasings = [
        'I feel suicidal tonight',
        'sometimes I think about self-harm',
        'there is no reason to live anymore',
        'my family would be better off without me',
      ];
      for (final phrase in phrasings) {
        final result = moderation.moderateContent(phrase);
        expect(result.crisisDetected, isTrue, reason: 'missed: $phrase');
        expect(result.isApproved, isTrue, reason: 'blocked: $phrase');
      }
    });

    test('ordinary supportive content does not trigger crisis flow', () {
      final result = moderation.moderateContent(
        'My tremor was better today after the morning walk.',
      );

      expect(result.isApproved, isTrue);
      expect(result.crisisDetected, isFalse);
      expect(result.supportMessage, isNull);
    });
  });

  group('Blocking violations', () {
    test('profanity is still blocked with an accurate reason', () {
      final result = moderation.moderateContent('This app is shit');

      expect(result.isApproved, isFalse);
      expect(result.rejectionReason, contains('community guidelines'));
    });

    test('blocked crisis post still carries support resources', () {
      final result = moderation.moderateContent(
        'This app is shit and I want to die',
      );

      expect(result.isApproved, isFalse);
      expect(result.rejectionReason, contains('community guidelines'));
      expect(result.crisisDetected, isTrue);
      expect(result.supportMessage, ContentModerationService.crisisMessage);
    });

    test('empty content is rejected', () {
      final result = moderation.moderateContent('   ');

      expect(result.isApproved, isFalse);
      expect(
        result.violations.single.type,
        ViolationType.emptyContent,
      );
    });

    test('overlong content is rejected with the length reason', () {
      final result = moderation.moderateContent('a b c ' * 400);

      expect(result.isApproved, isFalse);
      expect(result.rejectionReason, contains('maximum length'));
    });
  });

  group('Non-blocking violations', () {
    test('links are flagged but do not block', () {
      final result = moderation.moderateContent(
        'I found this helpful reading at https://example.com/article',
      );

      expect(result.isApproved, isTrue);
      expect(
        result.violations.map((v) => v.type),
        contains(ViolationType.linkSpam),
      );
    });

    test('excessive caps are flagged but do not block', () {
      final result = moderation.moderateContent(
        'MY MEDICATION SCHEDULE CHANGED TODAY AND I AM WORRIED',
      );

      expect(result.isApproved, isTrue);
      expect(
        result.violations.map((v) => v.type),
        contains(ViolationType.excessiveCaps),
      );
    });
  });
}
