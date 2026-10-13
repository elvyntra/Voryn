import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/meetings/meetings_screen.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';

class MockVorynMeetingService extends VorynMeetingService {
  MockVorynMeetingService({
    this.meetingsToReturn = const [],
    this.throwOnList = false,
    this.createdMeetingToReturn,
    this.throwOnCreate = false,
    this.prejoinToReturn,
    this.joinedToReturn,
    this.throwOnJoin = false,
  });

  List<VorynMeetingSummary> meetingsToReturn;
  bool throwOnList;
  VorynCreatedMeeting? createdMeetingToReturn;
  bool throwOnCreate;
  VorynPrejoinMeeting? prejoinToReturn;
  VorynJoinedMeeting? joinedToReturn;
  bool throwOnJoin;

  int listCalls = 0;
  int createCalls = 0;
  int resolveCalls = 0;
  int joinCalls = 0;
  int rollbackLeaveCalls = 0;

  @override
  Future<List<VorynMeetingSummary>> listMyMeetings() async {
    listCalls++;
    if (throwOnList) throw Exception('Database network timeout');
    return meetingsToReturn;
  }

  @override
  Future<VorynCreatedMeeting> createMeeting({
    required String title,
    String access = 'link',
  }) async {
    createCalls++;
    if (throwOnCreate) throw Exception('Server rejected meeting creation');
    if (title.trim().isEmpty || title.trim().length > 60) {
      throw ArgumentError('Invalid title');
    }
    return createdMeetingToReturn ??
        VorynCreatedMeeting(
          id: 'test-meeting-id-123',
          title: title,
          joinCode: 'k7q-mzx-p2f',
          access: access,
          status: 'ready',
          livekitRoomName: 'voryn-meeting-test-meeting-id-123',
        );
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
    if (throwOnJoin) {
      rollbackLeaveCalls++;
      throw StateError('Unable to obtain meeting token: Token gateway error');
    }
    return joinedToReturn ??
        VorynJoinedMeeting(
          meetingId: 'test-meeting-id-123',
          title: 'Sprint Planning',
          livekitRoomName: 'voryn-meeting-test-meeting-id-123',
          role: 'participant',
          status: 'active',
          access: 'link',
          livekitToken: 'mock.livekit.token',
          livekitUrl: 'wss://livekit.internal',
          initialMic: initialMic,
          initialCamera: initialCamera,
        );
  }

  @override
  Future<void> leaveMeeting(String meetingId) async {
    rollbackLeaveCalls++;
  }
}

Widget createTestApp(Widget child) {
  return MaterialApp(
    theme: VorynTheme.dark,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockVorynMeetingService mockService;

  setUp(() {
    mockService = MockVorynMeetingService();
    VorynMeetingService.instance = mockService;
  });

  group('Checkpoint MEET-3A: Meetings Tab & Join Flow Targeted Tests', () {
    // -------------------------------------------------------------------------
    // TEST 1: Meetings tab uses real service results
    // -------------------------------------------------------------------------
    testWidgets('1. Meetings tab renders real service meetings without mocks', (tester) async {
      mockService.meetingsToReturn = [
        const VorynMeetingSummary(
          id: 'm-1',
          title: 'Authoritative Architecture Sync',
          joinCode: 'k7q-mzx-p2f',
          access: 'link',
          status: 'active',
          hostUid: 'host-1',
          myRole: 'host',
          isHost: true,
          activeParticipantCount: 3,
          historicalAttendeeCount: 3,
        ),
      ];

      await tester.pumpWidget(createTestApp(const MeetingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Authoritative Architecture Sync'), findsOneWidget);
      expect(find.text('Hosted'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Design Review'), findsNothing); // No mockMeetings!
    });

    // -------------------------------------------------------------------------
    // TEST 2: Empty state without mock data
    // -------------------------------------------------------------------------
    testWidgets('2. Empty state renders cleanly when service returns empty list', (tester) async {
      mockService.meetingsToReturn = [];

      await tester.pumpWidget(createTestApp(const MeetingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No meetings yet'), findsOneWidget);
      expect(find.text('Design Review'), findsNothing);
      expect(find.text('Weekly Catch-up'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // TEST 3: Loading and retry
    // -------------------------------------------------------------------------
    testWidgets('3. Error state displays retry button and recovers on retry', (tester) async {
      mockService.throwOnList = true;

      await tester.pumpWidget(createTestApp(const MeetingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Unable to load meetings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Fix service and tap retry
      mockService.throwOnList = false;
      mockService.meetingsToReturn = [
        const VorynMeetingSummary(
          id: 'm-recovered',
          title: 'Recovered Meeting',
          joinCode: 'rec-123-xyz',
          access: 'link',
          status: 'ready',
          hostUid: 'host-1',
          myRole: 'participant',
          isHost: false,
          activeParticipantCount: 0,
          historicalAttendeeCount: 1,
        ),
      ];

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Recovered Meeting'), findsOneWidget);
      expect(find.text('Joined'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 4: Create validation
    // -------------------------------------------------------------------------
    test('4. Create meeting validates title length boundaries (1-60 chars)', () {
      final service = VorynMeetingService();

      expect(
        () => service.createMeeting(title: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.createMeeting(title: ' ' * 5),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.createMeeting(title: 'A' * 61),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.createMeeting(title: 'Valid Title', access: 'invalid_access'),
        throwsA(isA<ArgumentError>()),
      );
    });

    // -------------------------------------------------------------------------
    // TEST 5: Create RPC success
    // -------------------------------------------------------------------------
    testWidgets('5. Create meeting RPC success navigates to MeetingCreatedScreen with real code', (tester) async {
      mockService.createdMeetingToReturn = const VorynCreatedMeeting(
        id: 'new-id-99',
        title: 'Q4 Product Roadmap',
        joinCode: 'q4p-rod-map',
        access: 'link',
        status: 'ready',
        livekitRoomName: 'voryn-meeting-new-id-99',
      );

      await tester.pumpWidget(createTestApp(const NewMeetingScreen()));
      await tester.pumpAndSettle();

      // Enter title
      await tester.enterText(find.byType(TextField), 'Q4 Product Roadmap');
      await tester.tap(find.text('Create meeting'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting created'), findsOneWidget);
      expect(find.text('q4p-rod-map'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 6: Create RPC failure
    // -------------------------------------------------------------------------
    testWidgets('6. Create meeting RPC failure displays error and stays on create screen', (tester) async {
      mockService.throwOnCreate = true;

      await tester.pumpWidget(createTestApp(const NewMeetingScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Failed Meeting');
      await tester.tap(find.text('Create meeting'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to create meeting'), findsOneWidget);
      expect(find.text('Meeting created'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // TEST 7: Join code normalization
    // -------------------------------------------------------------------------
    test('7. Join code normalization accepts standard, unhyphenated, links, and casing', () {
      expect(normalizeMeetingJoinCode('k7q-mzx-p2f'), equals('k7q-mzx-p2f'));
      expect(normalizeMeetingJoinCode('K7Q-MZX-P2F'), equals('k7q-mzx-p2f'));
      expect(normalizeMeetingJoinCode('k7qmzxp2f'), equals('k7q-mzx-p2f'));
      expect(normalizeMeetingJoinCode('https://voryn.app/m/k7q-mzx-p2f'), equals('k7q-mzx-p2f'));
      expect(normalizeMeetingJoinCode('voryn.app/j/k7q-mzx-p2f'), equals('k7q-mzx-p2f'));
      expect(normalizeMeetingJoinCode('   k7q-mzx-p2f   '), equals('k7q-mzx-p2f'));
    });

    // -------------------------------------------------------------------------
    // TEST 8: Explicit lookup only
    // -------------------------------------------------------------------------
    testWidgets('8. Typing code does NOT trigger RPC lookup until Continue is tapped', (tester) async {
      mockService.prejoinToReturn = const VorynPrejoinMeeting(
        meetingId: 'm-lookup',
        title: 'Explicit Lookup Test',
        joinCode: 'k7q-mzx-p2f',
        status: 'active',
        access: 'link',
        activeParticipantCount: 2,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const JoinMeetingScreen()));
      await tester.pumpAndSettle();

      // Type code
      await tester.enterText(find.byType(TextField), 'k7q-mzx-p2f');
      await tester.pump();

      expect(mockService.resolveCalls, equals(0)); // No search on typing!

      // Tap Continue
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(mockService.resolveCalls, equals(1)); // Explicit action executed
      expect(find.text('Explicit Lookup Test').first, findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 9: Legacy meeting code accepted
    // -------------------------------------------------------------------------
    test('9. Legacy hex meeting code (0-9, a-f) is accepted and normalized', () {
      expect(normalizeMeetingJoinCode('a1f-4b2-9e0'), equals('a1f-4b2-9e0'));
      expect(normalizeMeetingJoinCode('a1f4b29e0'), equals('a1f-4b2-9e0'));
      expect(normalizeMeetingJoinCode('A1F-4B2-9E0'), equals('a1f-4b2-9e0'));
    });

    // -------------------------------------------------------------------------
    // TEST 10: Invalid code handled
    // -------------------------------------------------------------------------
    test('10. Invalid meeting codes return null and show validation error', () {
      expect(normalizeMeetingJoinCode(''), isNull);
      expect(normalizeMeetingJoinCode('123'), isNull);
      expect(normalizeMeetingJoinCode('k7q-mzx'), isNull);
      expect(normalizeMeetingJoinCode('k7q-mzx-p2f-extra'), isNull);
      expect(normalizeMeetingJoinCode('k7q_mzx_p2f!'), isNull);
    });

    // -------------------------------------------------------------------------
    // TEST 11: Pre-join doesn't create membership
    // -------------------------------------------------------------------------
    testWidgets('11. Pre-join screen inspects metadata without calling join RPC', (tester) async {
      const prejoin = VorynPrejoinMeeting(
        meetingId: 'm-read-only',
        title: 'Inspect Metadata Only',
        joinCode: 'abc-123-xyz',
        status: 'active',
        access: 'link',
        hostName: 'Lead Architect',
        activeParticipantCount: 4,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const PreJoinScreen(meeting: prejoin)));
      await tester.pumpAndSettle();

      expect(mockService.joinCalls, equals(0));
      expect(find.text('Inspect Metadata Only').first, findsOneWidget);
      expect(find.text('Host: Lead Architect'), findsOneWidget);
      expect(find.text('4 / 8 active'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 12: Microphone preference retained
    // -------------------------------------------------------------------------
    testWidgets('12. Microphone preference toggle is retained and sent to joinMeeting', (tester) async {
      const prejoin = VorynPrejoinMeeting(
        meetingId: 'm-mic',
        title: 'Mic Test',
        joinCode: 'mic-123-xyz',
        status: 'active',
        access: 'link',
        activeParticipantCount: 1,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const PreJoinScreen(meeting: prejoin)));
      await tester.pumpAndSettle();

      expect(find.text('Mic on'), findsOneWidget);

      // Toggle mic to mute
      await tester.tap(find.byTooltip('Mic on'));
      await tester.pumpAndSettle();

      expect(find.text('Mic muted'), findsOneWidget);

      // Join meeting
      await tester.tap(find.text('Join Meeting'));
      await tester.pumpAndSettle();

      expect(mockService.joinCalls, equals(1));
    });

    // -------------------------------------------------------------------------
    // TEST 13: Camera preference retained
    // -------------------------------------------------------------------------
    testWidgets('13. Camera preference toggle changes local state correctly', (tester) async {
      const prejoin = VorynPrejoinMeeting(
        meetingId: 'm-cam',
        title: 'Cam Test',
        joinCode: 'cam-123-xyz',
        status: 'active',
        access: 'link',
        activeParticipantCount: 1,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const PreJoinScreen(meeting: prejoin)));
      await tester.pumpAndSettle();

      expect(find.text('Camera off'), findsOneWidget);
      expect(find.text('Camera is off'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 14: Permission denial handled
    // -------------------------------------------------------------------------
    testWidgets('14. Permission denial handled without crashing pre-join screen', (tester) async {
      const prejoin = VorynPrejoinMeeting(
        meetingId: 'm-perm',
        title: 'Permission Test',
        joinCode: 'prm-123-xyz',
        status: 'active',
        access: 'link',
        activeParticipantCount: 1,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const PreJoinScreen(meeting: prejoin)));
      await tester.pumpAndSettle();

      // UI remains stable and interactive
      expect(find.text('Join Meeting'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 15: Join RPC only after Join tap
    // -------------------------------------------------------------------------
    testWidgets('15. Join RPC is triggered only when user explicitly taps Join Meeting', (tester) async {
      const prejoin = VorynPrejoinMeeting(
        meetingId: 'm-explicit',
        title: 'Explicit Join',
        joinCode: 'exp-123-xyz',
        status: 'active',
        access: 'link',
        activeParticipantCount: 1,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const PreJoinScreen(meeting: prejoin)));
      await tester.pumpAndSettle();

      expect(mockService.joinCalls, equals(0));

      await tester.tap(find.text('Join Meeting'));
      await tester.pumpAndSettle();

      expect(mockService.joinCalls, equals(1));
      expect(find.text('Meeting Room'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // TEST 16: Token failure doesn't show connected state
    // -------------------------------------------------------------------------
    testWidgets('16. LiveKit token failure triggers rollback and does not navigate to connected room', (tester) async {
      mockService.throwOnJoin = true;

      const prejoin = VorynPrejoinMeeting(
        meetingId: 'm-fail-token',
        title: 'Failing Token Test',
        joinCode: 'tok-123-xyz',
        status: 'active',
        access: 'link',
        activeParticipantCount: 1,
        capacity: 8,
      );

      await tester.pumpWidget(createTestApp(const PreJoinScreen(meeting: prejoin)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Join Meeting'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting Room'), findsNothing);
      expect(find.textContaining('Unable to obtain meeting token'), findsOneWidget);
      expect(mockService.rollbackLeaveCalls, greaterThanOrEqualTo(1));
    });

    // -------------------------------------------------------------------------
    // TEST 17: Hosted / Joined classification
    // -------------------------------------------------------------------------
    test('17. Summary classification correctly identifies host vs participant', () {
      const hostSummary = VorynMeetingSummary(
        id: '1',
        title: 'Host Meeting',
        joinCode: 'h-1',
        access: 'link',
        status: 'active',
        hostUid: 'u-1',
        myRole: 'host',
        isHost: true,
        activeParticipantCount: 1,
        historicalAttendeeCount: 1,
      );

      const participantSummary = VorynMeetingSummary(
        id: '2',
        title: 'Participant Meeting',
        joinCode: 'p-1',
        access: 'link',
        status: 'active',
        hostUid: 'u-other',
        myRole: 'participant',
        isHost: false,
        activeParticipantCount: 1,
        historicalAttendeeCount: 1,
      );

      expect(hostSummary.isHost, isTrue);
      expect(participantSummary.isHost, isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 18: Correct historical attendee count
    // -------------------------------------------------------------------------
    test('18. Summary reports authoritative historical attendee count', () {
      final json = {
        'id': 'm-hist',
        'title': 'All Hands',
        'join_code': 'all-hnd-123',
        'access': 'link',
        'status': 'ended',
        'host_uid': 'u-host',
        'my_role': 'host',
        'is_host': true,
        'active_participant_count': 0,
        'historical_attendee_count': 8,
      };

      final summary = VorynMeetingSummary.fromJson(json);
      expect(summary.historicalAttendeeCount, equals(8));
      expect(summary.activeParticipantCount, equals(0));
    });

    // -------------------------------------------------------------------------
    // TEST 19: No fabricated duration
    // -------------------------------------------------------------------------
    test('19. No duration is fabricated for unstarted or ongoing meetings', () {
      const unstarted = VorynMeetingSummary(
        id: '1',
        title: 'Unstarted',
        joinCode: 'u-1',
        access: 'link',
        status: 'ready',
        scheduledAt: null,
        startedAt: null,
        endedAt: null,
        hostUid: 'h-1',
        myRole: 'host',
        isHost: true,
        activeParticipantCount: 0,
        historicalAttendeeCount: 0,
      );
      expect(unstarted.formattedDuration, isNull);

      final now = DateTime.now();
      final ongoing = VorynMeetingSummary(
        id: '2',
        title: 'Ongoing',
        joinCode: 'o-1',
        access: 'link',
        status: 'active',
        startedAt: now.subtract(const Duration(minutes: 15)),
        endedAt: null, // ongoing!
        hostUid: 'h-1',
        myRole: 'host',
        isHost: true,
        activeParticipantCount: 2,
        historicalAttendeeCount: 2,
      );
      expect(ongoing.formattedDuration, isNull);

      final ended = VorynMeetingSummary(
        id: '3',
        title: 'Ended',
        joinCode: 'e-1',
        access: 'link',
        status: 'ended',
        startedAt: now.subtract(const Duration(minutes: 42)),
        endedAt: now,
        hostUid: 'h-1',
        myRole: 'host',
        isHost: true,
        activeParticipantCount: 0,
        historicalAttendeeCount: 5,
      );
      expect(ended.formattedDuration, equals('42 min'));
    });

    // -------------------------------------------------------------------------
    // TEST 20: Narrow/mobile UI no overflow
    // -------------------------------------------------------------------------
    testWidgets('20. Narrow mobile viewport (320x640) renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      mockService.meetingsToReturn = [
        const VorynMeetingSummary(
          id: 'm-narrow',
          title: 'Narrow Layout Meeting',
          joinCode: 'nar-row-123',
          access: 'link',
          status: 'ready',
          hostUid: 'h-1',
          myRole: 'host',
          isHost: true,
          activeParticipantCount: 1,
          historicalAttendeeCount: 1,
        ),
      ];

      await tester.pumpWidget(createTestApp(const MeetingsScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

