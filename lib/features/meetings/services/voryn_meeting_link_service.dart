import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/meeting_models.dart';

/// Represents a validated, canonical meeting link.
@immutable
class ParsedMeetingLink {
  const ParsedMeetingLink({
    required this.joinCode,
    required this.canonicalPath,
    this.canonicalUrl,
  });

  /// The normalized 9-character code in `xxx-xxx-xxx` format.
  final String joinCode;

  /// The canonical relative route path, e.g. `/m/abc-def-123`.
  final String canonicalPath;

  /// The full canonical URL if a valid public domain is configured, e.g. `https://domain/m/abc-def-123`.
  final String? canonicalUrl;
}

enum LinkParseFailureReason {
  empty,
  oversized,
  encodedSeparators,
  traversal,
  unsupportedScheme,
  unapprovedHost,
  unexpectedPath,
  extraSegments,
  uuidNotAllowed,
  malformedCode,
}

@immutable
class LinkParseResult {
  const LinkParseResult.success(this.link)
      : isSuccess = true,
        failureReason = null,
        errorMessage = null;

  const LinkParseResult.failure(this.failureReason, this.errorMessage)
      : isSuccess = false,
        link = null;

  final bool isSuccess;
  final ParsedMeetingLink? link;
  final LinkParseFailureReason? failureReason;
  final String? errorMessage;
}

/// Pending meeting intent preserved across authentication handoff.
@immutable
class PendingMeetingIntent {
  const PendingMeetingIntent({
    required this.joinCode,
    required this.createdAt,
    this.intendedForUserUid,
  });

  final String joinCode;
  final DateTime createdAt;
  final String? intendedForUserUid;

  bool isExpired({DateTime? now, Duration timeout = const Duration(minutes: 15)}) {
    final current = now ?? DateTime.now();
    return current.difference(createdAt) > timeout;
  }
}

/// Central parser, builder, and intent-coordinator for VoRyn meeting links.
class VorynMeetingLinkService {
  VorynMeetingLinkService._();

  static const MethodChannel _channel = MethodChannel('com.voryn.app/meeting_links');

  @visibleForTesting
  static String? overrideBaseUrl;

  /// Public base URL configured via environment or build-time definition.
  static String get publicBaseUrl {
    if (overrideBaseUrl != null) return overrideBaseUrl!.trim();
    return const String.fromEnvironment('VORYN_PUBLIC_BASE_URL', defaultValue: '').trim();
  }

  /// Whether a valid HTTPS public domain is configured for shareable links.
  static bool get isPublicDomainConfigured {
    if (publicBaseUrl.isEmpty) return false;
    final uri = Uri.tryParse(publicBaseUrl);
    return uri != null && uri.hasScheme && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// Approved hosts that may be accepted as incoming HTTPS meeting links.
  static Set<String> get approvedHosts {
    final hosts = <String>{};
    if (isPublicDomainConfigured) {
      final uri = Uri.tryParse(publicBaseUrl);
      if (uri != null && uri.host.isNotEmpty) {
        hosts.add(uri.host.toLowerCase());
      }
    }
    return hosts;
  }

  /// Builds a canonical shareable meeting link if a public domain is configured.
  /// If no public domain is configured, returns null (preventing fabricated links).
  static String? buildMeetingLink(String rawCode) {
    final normalized = normalizeMeetingJoinCode(rawCode);
    if (normalized == null) return null;
    if (!isPublicDomainConfigured) return null;

    final cleanBase = publicBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$cleanBase/m/$normalized';
  }

  // ===========================================================================
  // CENTRAL LINK PARSER
  // ===========================================================================

  /// Strict parser for incoming raw URLs, deep links, or path strings.
  static LinkParseResult parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.empty,
        'Meeting link is empty.',
      );
    }

    final trimmed = raw.trim();

    // 1. Oversized input check (limit: 500 characters)
    if (trimmed.length > 500) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.oversized,
        'Meeting link exceeds maximum allowed length.',
      );
    }

    final lower = trimmed.toLowerCase();

    // 2. Encoded separators check (%2f = '/', %5c = '\')
    if (lower.contains('%2f') || lower.contains('%5c') || trimmed.contains(r'\')) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.encodedSeparators,
        'Path separators cannot be encoded.',
      );
    }

    // 3. Path traversal check ('..' or '%2e%2e')
    if (lower.contains('..') || lower.contains('%2e%2e')) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.traversal,
        'Path traversal sequences are not permitted.',
      );
    }

    // 4. Reject client-supplied 36-char meeting UUIDs as join codes
    final uuidRegex = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false);
    if (uuidRegex.hasMatch(lower)) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.uuidNotAllowed,
        'Meeting UUID cannot be used as an invite join code.',
      );
    }

    String candidateCode;

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) {
        return const LinkParseResult.failure(
          LinkParseFailureReason.unsupportedScheme,
          'Malformed URL structure.',
        );
      }

      // Localhost/127.0.0.1 allowed for tests and local development
      final isLocalhost = uri.host == 'localhost' || uri.host == '127.0.0.1';
      final isApproved = approvedHosts.contains(uri.host.toLowerCase()) || isLocalhost;

      if (!isApproved) {
        return LinkParseResult.failure(
          LinkParseFailureReason.unapprovedHost,
          'Host "${uri.host}" is not an authorized VoRyn meeting link domain.',
        );
      }

      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty || (segments.first != 'm' && segments.first != 'meeting')) {
        return const LinkParseResult.failure(
          LinkParseFailureReason.unexpectedPath,
          'URL does not contain a meeting path (/m/...).',
        );
      }

      if (segments.length != 2) {
        return const LinkParseResult.failure(
          LinkParseFailureReason.extraSegments,
          'Meeting URL contains unexpected extra path segments.',
        );
      }

      candidateCode = segments[1];
    } else if (lower.startsWith('voryn://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) {
        return const LinkParseResult.failure(
          LinkParseFailureReason.unsupportedScheme,
          'Malformed custom scheme URL.',
        );
      }

      final host = uri.host.toLowerCase();
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

      if (host == 'm' || host == 'meeting') {
        if (segments.isEmpty) {
          return const LinkParseResult.failure(
            LinkParseFailureReason.unexpectedPath,
            'Meeting custom scheme URL is missing a code.',
          );
        }
        if (segments.length > 1) {
          return const LinkParseResult.failure(
            LinkParseFailureReason.extraSegments,
            'Meeting URL contains extra path segments.',
          );
        }
        candidateCode = segments.first;
      } else {
        return const LinkParseResult.failure(
          LinkParseFailureReason.unapprovedHost,
          'Custom scheme host must be "m" or "meeting".',
        );
      }
    } else if (trimmed.startsWith('/')) {
      final segments = trimmed.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty || (segments.first != 'm' && segments.first != 'meeting')) {
        return const LinkParseResult.failure(
          LinkParseFailureReason.unexpectedPath,
          'Route does not match /m/... path.',
        );
      }
      if (segments.length != 2) {
        return const LinkParseResult.failure(
          LinkParseFailureReason.extraSegments,
          'Route contains extra path segments.',
        );
      }
      candidateCode = segments[1];
    } else if (trimmed.contains('://')) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.unsupportedScheme,
        'Unsupported URL scheme.',
      );
    } else {
      candidateCode = trimmed;
    }

    final normalized = normalizeMeetingJoinCode(candidateCode);
    if (normalized == null) {
      return const LinkParseResult.failure(
        LinkParseFailureReason.malformedCode,
        'Invalid meeting code format. Codes must be 9 alphanumeric characters.',
      );
    }

    return LinkParseResult.success(
      ParsedMeetingLink(
        joinCode: normalized,
        canonicalPath: '/m/$normalized',
        canonicalUrl: isPublicDomainConfigured ? buildMeetingLink(normalized) : null,
      ),
    );
  }

  // ===========================================================================
  // AUTHENTICATION HANDOFF & INTENT ISOLATION
  // ===========================================================================

  static PendingMeetingIntent? _pendingIntent;

  @visibleForTesting
  static PendingMeetingIntent? get currentPendingIntent => _pendingIntent;

  static void setPendingIntent(String rawCode, {String? intendedForUserUid}) {
    final normalized = normalizeMeetingJoinCode(rawCode);
    if (normalized == null) return;

    _pendingIntent = PendingMeetingIntent(
      joinCode: normalized,
      createdAt: DateTime.now(),
      intendedForUserUid: intendedForUserUid,
    );
  }

  static String? consumePendingIntent({String? currentUserUid}) {
    final intent = _pendingIntent;
    if (intent == null) return null;

    _pendingIntent = null;

    if (intent.isExpired()) {
      debugPrint('[MEETING_LINK] pending intent for ${intent.joinCode} expired.');
      return null;
    }

    if (intent.intendedForUserUid != null &&
        currentUserUid != null &&
        intent.intendedForUserUid != currentUserUid) {
      debugPrint('[MEETING_LINK] pending intent isolated: account mismatch.');
      return null;
    }

    return intent.joinCode;
  }

  static void clearPendingIntent() {
    _pendingIntent = null;
  }

  // ===========================================================================
  // ANDROID PLATFORM CHANNEL LISTENER
  // ===========================================================================

  static final _linkStreamController = StreamController<String>.broadcast();
  static final _invitationStreamController = StreamController<String>.broadcast();
  static String? _lastHandledLink;

  static Stream<String> get onMeetingLinkReceived => _linkStreamController.stream;
  static Stream<String> get onMeetingInvitationReceived => _invitationStreamController.stream;

  static void notifyMeetingInvitationReceived(String joinCode) {
    final clean = joinCode.trim();
    if (clean.isNotEmpty) {
      _invitationStreamController.add(clean);
    }
  }

  static void initializePlatformBridge() {
    if (kIsWeb) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMeetingLink') {
        final url = call.arguments?['url'] as String? ?? call.arguments as String?;
        if (url != null && url.isNotEmpty) {
          handleIncomingRawLink(url);
        }
      } else if (call.method == 'onMeetingInvitation') {
        final code = call.arguments?['joinCode'] as String? ?? call.arguments as String?;
        if (code != null && code.isNotEmpty) {
          notifyMeetingInvitationReceived(code);
        }
      }
    });

    // Check cold-start initial link
    unawaited(_checkInitialMeetingLink());
  }

  static Future<void> _checkInitialMeetingLink() async {
    try {
      final initial = await _channel.invokeMethod<String>('getInitialMeetingLink');
      if (initial != null && initial.isNotEmpty) {
        handleIncomingRawLink(initial);
      }
    } catch (_) {}
  }

  /// Deduplicates and dispatches an incoming raw link.
  static bool handleIncomingRawLink(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;

    // Deduplicate rapid duplicate intent receipts
    if (_lastHandledLink == trimmed) {
      debugPrint('[MEETING_LINK] ignoring duplicate link: $trimmed');
      return false;
    }
    _lastHandledLink = trimmed;

    // Clear deduplication cache after 2 seconds
    Timer(const Duration(seconds: 2), () {
      if (_lastHandledLink == trimmed) _lastHandledLink = null;
    });

    _linkStreamController.add(trimmed);
    return true;
  }

  @visibleForTesting
  static void resetForTesting() {
    _pendingIntent = null;
    _lastHandledLink = null;
    overrideBaseUrl = null;
  }
}

