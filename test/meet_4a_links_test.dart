import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/meeting_direct_link_screen.dart';
import 'package:voryn/features/meetings/meetings_screen.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_link_service.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';

class MockTestMeetingService extends VorynMeetingService {
  MockTestMeetingService({
    this.prejoinToReturn,
    this.joinedToReturn,
    this.meetingsToReturn = const [],
  });

  VorynPrejoinMeeting? prejoinToReturn;
  VorynJoinedMeeting? joinedToReturn;
  List<VorynMeetingSummary> meetingsToReturn;

  int resolveCalls = 0;
  int joinCalls = 0;
  int listCalls = 0;

  @override
  Future<List<VorynMeetingSummary>> listMyMeetings() async {
    listCalls++;
    return meetingsToReturn;
  }

  @override
  Future<VorynPrejoinMeeting?> resolveMeetingForPrejoin(String rawCode) async {
    resolveCalls++;
    final norm = normalizeMeetingJoinCode(rawCode);
    if (norm == null) return null;
    return prejoinToReturn;
  }

  @override
  Future<VorynJoinedMeeting> joinMeeting(
    String rawCode, {
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    joinCalls++;
    return joinedToReturn ??
        VorynJoinedMeeting(
          meetingId: 'test-meeting-id',
          title: 'Test Meeting',
          livekitRoomName: 'voryn-meeting-test-meeting-id',
          role: 'participant',
          status: 'active',
          access: 'link',
          livekitToken: 'token',
          livekitUrl: 'wss://test.livekit.io',
          initialMic: initialMic,
          initialCamera: initialCamera,
        );
  }
}

void main() {
  setUp(() {
    VorynMeetingLinkService.resetForTesting();
  });

  tearDown(() {
    VorynMeetingLinkService.resetForTesting();
  });

  group('MEET-4A: Meeting Link Parser & Builder Security', () {
    test('1. Generates canonical meeting link when VORYN_PUBLIC_BASE_URL is configured', () {
      VorynMeetingLinkService.overrideBaseUrl = 'https://meet.voryn.app';
      final link = VorynMeetingLinkService.buildMeetingLink('abc-def-123');
      expect(link, 'https://meet.voryn.app/m/abc-def-123');
    });

    test('2. Strips trailing slashes from public base URL', () {
      VorynMeetingLinkService.overrideBaseUrl = 'https://meet.voryn.app///';
      final link = VorynMeetingLinkService.buildMeetingLink('k7q-mzx-p2f');
      expect(link, 'https://meet.voryn.app/m/k7q-mzx-p2f');
    });

    test('3. Returns null and prevents link fabrication when public base URL is empty', () {
      VorynMeetingLinkService.overrideBaseUrl = '';
      expect(VorynMeetingLinkService.isPublicDomainConfigured, isFalse);
      final link = VorynMeetingLinkService.buildMeetingLink('k7q-mzx-p2f');
      expect(link, isNull);
    });

    test('4. Correctly normalizes raw 9-char alphanumeric codes into 3-3-3 pattern', () {
      final res = VorynMeetingLinkService.parse('ABCDEF123');
      expect(res.isSuccess, isTrue);
      expect(res.link!.joinCode, 'abc-def-123');
      expect(res.link!.canonicalPath, '/m/abc-def-123');
    });

    test('5. Supports legacy 9-character hex codes (e.g., a1f-4b2-9e0)', () {
      final res = VorynMeetingLinkService.parse('A1F4B29E0');
      expect(res.isSuccess, isTrue);
      expect(res.link!.joinCode, 'a1f-4b2-9e0');
      expect(res.link!.canonicalPath, '/m/a1f-4b2-9e0');
    });

    test('6. Rejects malformed codes (too short, too long, invalid symbols)', () {
      expect(VorynMeetingLinkService.parse('abc').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('abc-def-12345').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('abc-def-12!').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('').isSuccess, isFalse);
      expect(VorynMeetingLinkService.parse('   ').isSuccess, isFalse);
    });

    test('7. Rejects unapproved external hosts in HTTPS links to prevent open redirects', () {
      VorynMeetingLinkService.overrideBaseUrl = 'https://voryn.app';
      final res = VorynMeetingLinkService.parse('https://evil.com/m/abc-def-123');
      expect(res.isSuccess, isFalse);
      expect(res.failureReason, LinkParseFailureReason.unapprovedHost);
    });

    test('8. Accepts approved host configured in VORYN_PUBLIC_BASE_URL', () {
      VorynMeetingLinkService.overrideBaseUrl = 'https://voryn.app';
      final res = VorynMeetingLinkService.parse('https://voryn.app/m/abc-def-123');
      expect(res.isSuccess, isTrue);
      expect(res.link!.joinCode, 'abc-def-123');
      expect(res.link!.canonicalPath, '/m/abc-def-123');
    });

    test('9. Rejects path traversal attempts (.. and %2e%2e)', () {
      final dotDot = VorynMeetingLinkService.parse('/m/../abc-def-123');
      expect(dotDot.isSuccess, isFalse);
      expect(dotDot.failureReason, LinkParseFailureReason.traversal);

      final encodedDot = VorynMeetingLinkService.parse('/m/%2e%2e/abc-def-123');
      expect(encodedDot.isSuccess, isFalse);
      expect(encodedDot.failureReason, LinkParseFailureReason.traversal);
    });

    test('10. Rejects encoded path separators (%2f, %5c, and backslashes)', () {
      final slash = VorynMeetingLinkService.parse('/m%2fabc-def-123');
      expect(slash.isSuccess, isFalse);
      expect(slash.failureReason, LinkParseFailureReason.encodedSeparators);

      final backslash = VorynMeetingLinkService.parse(r'/m\abc-def-123');
      expect(backslash.isSuccess, isFalse);
      expect(backslash.failureReason, LinkParseFailureReason.encodedSeparators);
    });

    test('11. Rejects oversized input strings (> 500 characters)', () {
      final oversized = 'a' * 501;
      final res = VorynMeetingLinkService.parse(oversized);
      expect(res.isSuccess, isFalse);
      expect(res.failureReason, LinkParseFailureReason.oversized);
    });

    test('12. Rejects meeting UUIDs as join codes', () {
      const uuid = 'c4b8b6f2-7e04-4c6e-8e83-7c9803274291';
      final res = VorynMeetingLinkService.parse('/m/$uuid');
      expect(res.isSuccess, isFalse);
      expect(res.failureReason, LinkParseFailureReason.uuidNotAllowed);
    });

    test('13. Parses Android custom scheme voryn://m/:code and voryn://meeting/:code', () {
      final mScheme = VorynMeetingLinkService.parse('voryn://m/abc-def-123');
      expect(mScheme.isSuccess, isTrue);
      expect(mScheme.link!.joinCode, 'abc-def-123');

      final meetingScheme = VorynMeetingLinkService.parse('voryn://meeting/xyz-987-uvw');
      expect(meetingScheme.isSuccess, isTrue);
      expect(meetingScheme.link!.joinCode, 'xyz-987-uvw');

      final invalidHost = VorynMeetingLinkService.parse('voryn://call/abc-def-123');
      expect(invalidHost.isSuccess, isFalse);
      expect(invalidHost.failureReason, LinkParseFailureReason.unapprovedHost);
    });

    test('14. Deduplicates identical links received within 2-second window', () async {
      final received = <String>[];
      final sub = VorynMeetingLinkService.onMeetingLinkReceived.listen(received.add);

      final first = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/abc-def-123');
      final duplicate = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/abc-def-123');
      final different = VorynMeetingLinkService.handleIncomingRawLink('voryn://m/999-888-777');

      await pumpEventQueue();

      expect(first, isTrue);
      expect(duplicate, isFalse);
      expect(different, isTrue);

      expect(received.length, 2);
      expect(received[0], 'voryn://m/abc-def-123');
      expect(received[1], 'voryn://m/999-888-777');

      await sub.cancel();
    });
  });

  group('MEET-4A: Authentication Handoff & Intent Isolation', () {
    test('15. Preserves pending meeting intent and restores on login', () {
      VorynMeetingLinkService.setPendingIntent('abc-def-123');
      expect(VorynMeetingLinkService.currentPendingIntent, isNotNull);
      expect(VorynMeetingLinkService.currentPendingIntent!.joinCode, 'abc-def-123');

      final consumed = VorynMeetingLinkService.consumePendingIntent(currentUserUid: 'user-1');
      expect(consumed, 'abc-def-123');
      expect(VorynMeetingLinkService.currentPendingIntent, isNull);
    });

    test('16. Expires pending meeting intent after 15 minutes', () {
      final intent = PendingMeetingIntent(
        joinCode: 'abc-def-123',
        createdAt: DateTime.now().subtract(const Duration(minutes: 16)),
      );
      expect(intent.isExpired(), isTrue);

      final freshIntent = PendingMeetingIntent(
        joinCode: 'abc-def-123',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      expect(freshIntent.isExpired(), isFalse);
    });

    test('17. Enforces user isolation if intendedForUserUid is specified', () {
      VorynMeetingLinkService.setPendingIntent('abc-def-123', intendedForUserUid: 'user-alice');
      
      // Mismatched user cannot consume Alice's intent
      final bobAttempt = VorynMeetingLinkService.consumePendingIntent(currentUserUid: 'user-bob');
      expect(bobAttempt, isNull);

      // Now reset and test matching user
      VorynMeetingLinkService.setPendingIntent('abc-def-123', intendedForUserUid: 'user-alice');
      final aliceAttempt = VorynMeetingLinkService.consumePendingIntent(currentUserUid: 'user-alice');
      expect(aliceAttempt, 'abc-def-123');
    });

    test('18. Sign-out clears any pending meeting intent', () {
      VorynMeetingLinkService.setPendingIntent('abc-def-123');
      expect(VorynMeetingLinkService.currentPendingIntent, isNotNull);

      VorynMeetingLinkService.clearPendingIntent();
      expect(VorynMeetingLinkService.currentPendingIntent, isNull);
    });
  });

  group('MEET-4A: UI Integration & Read-Only Resolution', () {
    testWidgets('19. Direct link screen validates code and shows error for malformed code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const MeetingDirectLinkScreen(rawCode: 'invalid!code'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Meeting Unavailable'), findsOneWidget);
      expect(find.text('Invalid meeting code format. Codes must be 9 alphanumeric characters.'), findsOneWidget);
    });

    testWidgets('20. Direct link screen prompts sign in and preserves intent when unauthenticated', (tester) async {
      final mockService = MockTestMeetingService();

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingDirectLinkScreen(
            rawCode: 'k7q-mzx-p2f',
            meetingService: mockService,
            isAuthenticated: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign In Required'), findsOneWidget);
      expect(find.text('Sign In to Continue'), findsOneWidget);
      expect(VorynMeetingLinkService.currentPendingIntent?.joinCode, 'k7q-mzx-p2f');
      expect(mockService.resolveCalls, 0);
      expect(mockService.joinCalls, 0);
    });

    testWidgets('21. Direct link screen resolves pre-join read-only and DOES NOT join automatically', (tester) async {
      final mockService = MockTestMeetingService(
        prejoinToReturn: const VorynPrejoinMeeting(
          meetingId: 'meet-123',
          title: 'Design Sync',
          joinCode: 'k7q-mzx-p2f',
          status: 'ready',
          access: 'link',
          activeParticipantCount: 1,
          capacity: 50,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingDirectLinkScreen(
            rawCode: 'k7q-mzx-p2f',
            meetingService: mockService,
            isAuthenticated: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verified: resolveMeetingForPrejoin was called
      expect(mockService.resolveCalls, 1);
      // STRICT REQUIREMENT: joinMeeting was NOT called!
      expect(mockService.joinCalls, 0);

      // Renders PreJoinScreen with meeting title and explicit Join button
      expect(find.text('Design Sync'), findsAtLeastNWidgets(1));
      expect(find.text('Join Meeting'), findsOneWidget);
    });

    testWidgets('22. Direct link screen handles ended meeting gracefully', (tester) async {
      final mockService = MockTestMeetingService(
        prejoinToReturn: const VorynPrejoinMeeting(
          meetingId: 'meet-ended',
          title: 'Finished Sync',
          joinCode: 'k7q-mzx-p2f',
          status: 'ended',
          access: 'link',
          activeParticipantCount: 0,
          capacity: 50,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingDirectLinkScreen(
            rawCode: 'k7q-mzx-p2f',
            meetingService: mockService,
            isAuthenticated: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Meeting Unavailable'), findsOneWidget);
      expect(find.text('This meeting has already ended.'), findsOneWidget);
      expect(mockService.joinCalls, 0);
    });

    testWidgets('23. MeetingCreatedScreen displays Copy Code always, and Copy Link when domain configured', (tester) async {
      const testMeeting = VorynCreatedMeeting(
        id: 'created-123',
        title: 'Standup',
        joinCode: 'abc-def-123',
        access: 'link',
        status: 'ready',
        livekitRoomName: 'voryn-meeting-created-123',
      );

      // Without configured domain:
      VorynMeetingLinkService.overrideBaseUrl = null;
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const MeetingCreatedScreen(meeting: testMeeting),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy Code'), findsOneWidget);
      expect(find.text('Copy Link'), findsNothing);

      // With configured domain:
      VorynMeetingLinkService.overrideBaseUrl = 'https://meet.voryn.app';
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const MeetingCreatedScreen(meeting: testMeeting),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy Code'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
    });

    testWidgets('24. MeetingDetailsScreen displays Copy Meeting Link when domain configured', (tester) async {
      final summary = VorynMeetingSummary(
        id: 'summary-123',
        title: 'Retro',
        joinCode: 'abc-def-123',
        status: 'active',
        isHost: true,
        access: 'link',
        hostUid: 'host-1',
        myRole: 'host',
        activeParticipantCount: 3,
        historicalAttendeeCount: 3,
      );

      VorynMeetingLinkService.overrideBaseUrl = 'https://meet.voryn.app';
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingDetailsScreen(
            meeting: summary,
            meetingId: 'summary-123',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy Meeting Link'), findsOneWidget);
    });

    testWidgets('25. MeetingDirectLinkScreen shows back arrow and navigates back cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const MeetingDirectLinkScreen(
            rawCode: 'invalid',
            isAuthenticated: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });
  });
}

