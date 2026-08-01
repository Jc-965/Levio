import 'package:profanity_filter/profanity_filter.dart';
import 'app_logger.dart';

/// Content moderation result containing filtering details
class ModerationResult {
  final bool isApproved;
  final String? sanitizedContent;
  final List<String> flaggedWords;
  final List<ModerationViolation> violations;
  final String? rejectionReason;

  /// Set when the content discloses a mental health crisis. The content is
  /// still allowed; the UI should surface [supportMessage] alongside it.
  final bool crisisDetected;
  final String? supportMessage;

  ModerationResult({
    required this.isApproved,
    this.sanitizedContent,
    this.flaggedWords = const [],
    this.violations = const [],
    this.rejectionReason,
    this.crisisDetected = false,
    this.supportMessage,
  });

  factory ModerationResult.approved(String content) =>
      ModerationResult(isApproved: true, sanitizedContent: content);

  factory ModerationResult.rejected(
    String reason, {
    List<ModerationViolation>? violations,
  }) => ModerationResult(
    isApproved: false,
    rejectionReason: reason,
    violations: violations ?? [],
  );
}

/// Types of content violations
enum ViolationType {
  profanity,
  spam,
  personalInfo,
  excessiveCaps,
  repetitiveContent,
  tooShort,
  tooLong,
  emptyContent,
  linkSpam,
  harassment,
  crisisSupport,
}

/// Details about a specific violation
class ModerationViolation {
  final ViolationType type;
  final String description;
  final String? matchedContent;

  ModerationViolation({
    required this.type,
    required this.description,
    this.matchedContent,
  });
}

/// Production-grade content moderation service
///
/// Features:
/// - Multi-language profanity detection using LDNOOBW word list
/// - Spam pattern detection (URLs, emails, phone numbers)
/// - Crisis-language detection that attaches support resources without
///   blocking or censoring the disclosure
/// - Content length validation
/// - Excessive caps detection
/// - Repetitive content detection
/// - Detailed violation reporting
class ContentModerationService {
  static final ContentModerationService _instance =
      ContentModerationService._internal();
  factory ContentModerationService() => _instance;

  final AppLogger _logger = AppLogger();
  late final ProfanityFilter _profanityFilter;

  // Configuration
  static const int minContentLength = 1;
  static const int maxContentLength = 2000;
  static const int maxPostsPerHour = 10;
  static const double maxCapsRatio = 0.6;
  static const int repetitionThreshold = 3;

  // Phrases that suggest the author may be in crisis. These are never
  // treated as profanity: a disclosure of distress must not be blocked,
  // censored, or described as inappropriate language. Detection only
  // attaches support resources to the moderation result.
  static const List<String> _crisisSupportTerms = [
    'suicide',
    'suicidal',
    'kill myself',
    'end my life',
    'end it all',
    'want to die',
    'self harm',
    'self-harm',
    'hurt myself',
    'overdose',
    'no reason to live',
    'better off without me',
  ];

  // Crisis resources to show when concerning content is detected
  static const String crisisMessage =
      'You are not alone. If you are thinking about suicide or self-harm, '
      'help is available right now: contact your local emergency number or '
      'a suicide prevention helpline (in the US, call or text 988).';

  ContentModerationService._internal() {
    // Initialize with the default LDNOOBW word list only. Crisis terms are
    // deliberately kept out of the profanity filter so they are never
    // censored or reported as inappropriate language.
    _profanityFilter = ProfanityFilter();
  }

  /// Moderate content with comprehensive checks
  ///
  /// Returns a [ModerationResult] with approval status and details
  ModerationResult moderateContent(
    String content, {
    bool allowLinks = false,
    bool strictMode = true,
    String? userId,
  }) {
    final violations = <ModerationViolation>[];

    // 1. Check for empty content
    if (content.trim().isEmpty) {
      return ModerationResult.rejected(
        'Content cannot be empty',
        violations: [
          ModerationViolation(
            type: ViolationType.emptyContent,
            description: 'The content is empty or contains only whitespace',
          ),
        ],
      );
    }

    // 2. Check content length
    final lengthResult = _checkContentLength(content.trim());
    if (lengthResult != null) {
      violations.add(lengthResult);
    }

    // 3. Check for profanity using professional filter
    final profanityResult = _checkProfanity(content);
    if (profanityResult != null) {
      violations.add(profanityResult);

      // Log moderation event
      _logger.moderation(
        'profanity_detected',
        reason: 'Profanity found in content',
      );
    }

    // 4. Check for crisis language. Never blocks; surfaces support resources.
    final crisisResult = _checkCrisisLanguage(content);
    if (crisisResult != null) {
      violations.add(crisisResult);

      _logger.moderation(
        'crisis_support_shown',
        reason: 'Crisis language detected, support resources attached',
      );
    }

    // 5. Check for spam patterns
    final spamResult = _checkSpamPatterns(content, allowLinks: allowLinks);
    violations.addAll(spamResult);

    // 6. Check for excessive caps (shouting)
    final capsResult = _checkExcessiveCaps(content);
    if (capsResult != null) {
      violations.add(capsResult);
    }

    // 7. Check for repetitive content
    final repetitionResult = _checkRepetitiveContent(content);
    if (repetitionResult != null) {
      violations.add(repetitionResult);
    }

    // Determine final result
    final crisisDetected = violations.any(
      (v) => v.type == ViolationType.crisisSupport,
    );

    bool isBlocking(ModerationViolation v) =>
        v.type == ViolationType.profanity ||
        v.type == ViolationType.harassment ||
        v.type == ViolationType.tooLong ||
        v.type == ViolationType.emptyContent;

    final blockingViolations = violations.where(isBlocking).toList();

    if (blockingViolations.isNotEmpty) {
      // Explain the actual blocking violation, not whichever check ran first.
      final primaryViolation = blockingViolations.first;
      return ModerationResult(
        isApproved: false,
        violations: violations,
        rejectionReason: _getHumanReadableReason(primaryViolation),
        flaggedWords: _profanityFilter.hasProfanity(content)
            ? _profanityFilter.getAllProfanity(content)
            : [],
        crisisDetected: crisisDetected,
        supportMessage: crisisDetected ? crisisMessage : null,
      );
    }

    // Content approved - return sanitized version
    String sanitized = content;
    if (_profanityFilter.hasProfanity(content)) {
      sanitized = _profanityFilter.censor(content);
    }

    return ModerationResult(
      isApproved: true,
      sanitizedContent: sanitized,
      violations: violations, // May have minor violations
      crisisDetected: crisisDetected,
      supportMessage: crisisDetected ? crisisMessage : null,
    );
  }

  /// Quick check if content contains profanity
  bool hasProfanity(String content) {
    return _profanityFilter.hasProfanity(content);
  }

  /// Get censored version of content
  String censorContent(String content) {
    return _profanityFilter.censor(content);
  }

  /// Get all profane words found in content
  List<String> getProfaneWords(String content) {
    return _profanityFilter.getAllProfanity(content);
  }

  // Private helper methods

  ModerationViolation? _checkContentLength(String content) {
    if (content.length < minContentLength) {
      return ModerationViolation(
        type: ViolationType.tooShort,
        description: 'Content must be at least $minContentLength character(s)',
      );
    }
    if (content.length > maxContentLength) {
      return ModerationViolation(
        type: ViolationType.tooLong,
        description:
            'Content exceeds maximum length of $maxContentLength characters',
      );
    }
    return null;
  }

  ModerationViolation? _checkProfanity(String content) {
    if (_profanityFilter.hasProfanity(content)) {
      final profaneWords = _profanityFilter.getAllProfanity(content);
      return ModerationViolation(
        type: ViolationType.profanity,
        description: 'Content contains inappropriate language',
        matchedContent: profaneWords.isNotEmpty
            ? '${profaneWords.length} word(s) flagged'
            : null,
      );
    }
    return null;
  }

  ModerationViolation? _checkCrisisLanguage(String content) {
    final lowerContent = content.toLowerCase();
    for (final term in _crisisSupportTerms) {
      if (lowerContent.contains(term)) {
        return ModerationViolation(
          type: ViolationType.crisisSupport,
          description: crisisMessage,
          matchedContent: null, // Don't expose matched term
        );
      }
    }
    return null;
  }

  List<ModerationViolation> _checkSpamPatterns(
    String content, {
    bool allowLinks = false,
  }) {
    final violations = <ModerationViolation>[];

    // URL detection
    final urlPattern = RegExp(
      r'https?:\/\/[^\s]+|www\.[^\s]+',
      caseSensitive: false,
    );
    if (!allowLinks && urlPattern.hasMatch(content)) {
      violations.add(
        ModerationViolation(
          type: ViolationType.linkSpam,
          description: 'Links are not allowed in posts',
        ),
      );
    }

    // Email detection
    final emailPattern = RegExp(
      r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
    );
    if (emailPattern.hasMatch(content)) {
      violations.add(
        ModerationViolation(
          type: ViolationType.personalInfo,
          description: 'Please do not share email addresses',
        ),
      );
    }

    // Phone number detection (various formats)
    final phonePattern = RegExp(
      r'\b(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b',
    );
    if (phonePattern.hasMatch(content)) {
      violations.add(
        ModerationViolation(
          type: ViolationType.personalInfo,
          description: 'Please do not share phone numbers',
        ),
      );
    }

    // Spam keywords
    final spamKeywords = [
      'buy now',
      'click here',
      'free money',
      'act now',
      'limited time',
      'congratulations you won',
      'winner',
      'earn money fast',
      'make money online',
    ];
    final lowerContent = content.toLowerCase();
    for (final keyword in spamKeywords) {
      if (lowerContent.contains(keyword)) {
        violations.add(
          ModerationViolation(
            type: ViolationType.spam,
            description: 'Content appears to be spam',
          ),
        );
        break;
      }
    }

    return violations;
  }

  ModerationViolation? _checkExcessiveCaps(String content) {
    final letters = content.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.length < 10) return null; // Too short to judge

    final upperCount = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
    final ratio = upperCount / letters.length;

    if (ratio > maxCapsRatio) {
      return ModerationViolation(
        type: ViolationType.excessiveCaps,
        description: 'Please avoid using excessive capital letters',
      );
    }
    return null;
  }

  ModerationViolation? _checkRepetitiveContent(String content) {
    // Check for repeated characters (e.g., "aaaaaaaa")
    final repeatedChars = RegExp(r'(.)\1{5,}');
    if (repeatedChars.hasMatch(content)) {
      return ModerationViolation(
        type: ViolationType.repetitiveContent,
        description: 'Content contains excessive repeated characters',
      );
    }

    // Check for repeated words
    final words = content.toLowerCase().split(RegExp(r'\s+'));
    final wordCounts = <String, int>{};
    for (final word in words) {
      if (word.length > 2) {
        wordCounts[word] = (wordCounts[word] ?? 0) + 1;
      }
    }

    final totalWords = words.length;
    for (final entry in wordCounts.entries) {
      // If a word appears more than 30% of the time and at least 4 times
      if (entry.value >= 4 && entry.value / totalWords > 0.3) {
        return ModerationViolation(
          type: ViolationType.repetitiveContent,
          description: 'Content contains too much repetition',
        );
      }
    }

    return null;
  }

  String _getHumanReadableReason(ModerationViolation violation) {
    switch (violation.type) {
      case ViolationType.profanity:
        return 'Your post contains language that violates our community guidelines.';
      case ViolationType.spam:
        return 'Your post was flagged as potential spam.';
      case ViolationType.personalInfo:
        return 'For your safety, please do not share personal contact information.';
      case ViolationType.excessiveCaps:
        return 'Please avoid using excessive capital letters.';
      case ViolationType.repetitiveContent:
        return 'Your post contains too much repetitive content.';
      case ViolationType.tooShort:
        return 'Your post is too short. Please add more detail.';
      case ViolationType.tooLong:
        return 'Your post exceeds the maximum length. Please shorten it.';
      case ViolationType.emptyContent:
        return 'Your post cannot be empty.';
      case ViolationType.linkSpam:
        return 'Links are not allowed in posts for safety reasons.';
      case ViolationType.harassment:
        return violation.description;
      case ViolationType.crisisSupport:
        // Crisis support never blocks content; this reason is only shown if
        // some other violation blocked the post.
        return crisisMessage;
    }
  }
}
