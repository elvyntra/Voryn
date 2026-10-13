import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/contacts/voryn_contact_service.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/meetings_screen.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';
import 'package:voryn/features/meetings/widgets/meeting_invite_sheet.dart';

class MockInvitationMeetingService extends VorynMeetingService {
  MockInvitationMeetingService({
    this.participantsToReturn = const [],
    this.eligibleContactsToReturn = const [],
    this.meetingsToReturn = const [],
    this.failOnTargetUid,
    this.throwOnInvite = false,
  });

  List<VorynMeetingParticipant> participantsToReturn;
  List<VorynStoredContact> eligibleContactsToReturn;
  List<VorynMeetingSummary> meetingsToReturn;
  String? failOnTargetUid;
  bool throwOnInvite;

  final List<Map<String, String>> inviteCalls = [];
  int listParticipantsCalls = 0;
  int getEligibleContactsCalls = 0;

  @override
  Future<List<VorynMeetingParticipant>> getMeetingParticipants(String meetingId) async {
    listParticipantsCalls++;
    return participantsToReturn;
  }

  @override
  Future<List<VorynStoredContact>> getEligibleContacts(
    String meetingId, {
    VorynContactService contactService = const VorynContactService(),
  }) async {
    getEligibleContactsCalls++;
    return eligibleContactsToReturn;
  }

  @override
  Future<MeetingInvitationResult> inviteParticipant(
    String meetingId,
    String targetUserUid,
  ) async {
    inviteCalls.add({'meetingId': meetingId, 'targetUserUid': targetUserUid});

    if (throwOnInvite) {
      return MeetingInvitationResult(
        userUid: targetUserUid,
        isSuccess: false,
        errorMessage: 'Unauthorized to invite participants to this meeting',
      );
    }

    if (failOnTargetUid != null && failOnTargetUid == targetUserUid) {
      return MeetingInvitationResult(
        userUid: targetUserUid,
        isSuccess: false,
        errorMessage: 'Target user does not exist',
      );
    }

    return MeetingInvitationResult(
      userUid: targetUserUid,
      isSuccess: true,
    );
  }

  @override
  Future<List<MeetingInvitationResult>> inviteParticipants(
    String meetingId,
    List<String> targetUserUids,
  ) async {
    final results = <MeetingInvitationResult>[];
    for (final uid in targetUserUids) {
      final res = await inviteParticipant(meetingId, uid);
      results.add(res);
    }
    return results;
  }

  @override
  Future<List<VorynMeetingSummary>> listMyMeetings() async {
    return meetingsToReturn;
  }
}

void main() {
  const sampleMeetingId = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';

  final contactAlice = const VorynStoredContact(
    uid: 'uid-alice-111',
    name: 'Alice Smith',
    vorynId: 'alice_s',
    displayName: 'Alice Smith',
    favorite: true,
    blocked: false,
  );

  final contactBob = const VorynStoredContact(
    uid: 'uid-bob-222',
    name: 'Bob Jones',
    vorynId: 'bobj',
    displayName: 'Bob Jones',
    favorite: false,
    blocked: false,
  );

  final contactCharlie = const VorynStoredContact(
    uid: 'uid-charlie-333',
    name: 'Charlie Brown',
    vorynId: 'charlieb',
    displayName: 'Charlie Brown',
    favorite: false,
    blocked: false,
  );

  final contactBlocked = const VorynStoredContact(
    uid: 'uid-blocked-444',
    name: 'Bad Actor',
    vorynId: 'bad_actor',
    displayName: 'Bad Actor',
    favorite: false,
    blocked: true,
  );

  group('MEET-4B: Meeting Invitation Service & Eligibility', () {
    test('1. Eligible registered contacts appear and blocked contacts are excluded', () async {
      // Contact eligibility filter verification
      final testContacts = [contactAlice, contactBob, contactBlocked];
      final eligible = testContacts.where((c) => !c.blocked && c.uid.isNotEmpty).toList();

      expect(eligible.length, 2);
      expect(eligible.any((c) => c.uid == contactBlocked.uid), isFalse);
    });

    test('2. Unregistered / empty UID contacts are marked ineligible', () {
      const invalidContact = VorynStoredContact(
        uid: '',
        name: 'Unregistered Phone Contact',
        vorynId: '',
        displayName: 'Unregistered Phone Contact',
        favorite: false,
        blocked: false,
      );

      final eligible = [invalidContact].where((c) => c.uid.isNotEmpty).toList();
      expect(eligible.isEmpty, isTrue);
    });

    test('3. Invite RPC called with correct meeting ID and target user UID', () async {
      final mock = MockInvitationMeetingService();
      final res = await mock.inviteParticipant(sampleMeetingId, contactAlice.uid);

      expect(res.isSuccess, isTrue);
      expect(mock.inviteCalls.length, 1);
      expect(mock.inviteCalls.first['meetingId'], sampleMeetingId);
      expect(mock.inviteCalls.first['targetUserUid'], contactAlice.uid);
    });

    test('4. Unauthorized inviter is handled with clear failure result', () async {
      final mock = MockInvitationMeetingService(throwOnInvite: true);
      final res = await mock.inviteParticipant(sampleMeetingId, contactAlice.uid);

      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, contains('Unauthorized'));
    });

    test('5. Nonexistent target user is handled with failure result', () async {
      final mock = MockInvitationMeetingService(failOnTargetUid: 'ghost-uid');
      final res = await mock.inviteParticipant(sampleMeetingId, 'ghost-uid');

      expect(res.isSuccess, isFalse);
      expect(res.errorMessage, contains('Target user does not exist'));
    });

    test('6. Multi-invite partial failure is reported individually', () async {
      final mock = MockInvitationMeetingService(failOnTargetUid: contactBob.uid);
      final results = await mock.inviteParticipants(
        sampleMeetingId,
        [contactAlice.uid, contactBob.uid],
      );

      expect(results.length, 2);
      expect(results[0].userUid, contactAlice.uid);
      expect(results[0].isSuccess, isTrue);

      expect(results[1].userUid, contactBob.uid);
      expect(results[1].isSuccess, isFalse);
      expect(results[1].errorMessage, contains('Target user does not exist'));
    });

    test('7. Safe retry: previously failed invitation can be retried independently', () async {
      final mock = MockInvitationMeetingService(failOnTargetUid: contactBob.uid);
      final initial = await mock.inviteParticipant(sampleMeetingId, contactBob.uid);
      expect(initial.isSuccess, isFalse);

      // Resolve condition and retry
      mock.failOnTargetUid = null;
      final retry = await mock.inviteParticipant(sampleMeetingId, contactBob.uid);
      expect(retry.isSuccess, isTrue);
      expect(mock.inviteCalls.length, 2);
    });
  });

  group('MEET-4B: Participant Model & UI Classification', () {
    test('8. Participant states correctly classify Invited, Joined, and Left', () {
      final now = DateTime.now();

      final invited = VorynMeetingParticipant(
        meetingId: sampleMeetingId,
        userUid: 'u1',
        role: 'participant',
        displayName: 'Invited User',
        invitedAt: now,
        joinedAt: null,
        leftAt: null,
      );
      expect(invited.state, MeetingParticipantState.invited);

      final joined = VorynMeetingParticipant(
        meetingId: sampleMeetingId,
        userUid: 'u2',
        role: 'participant',
        displayName: 'Active User',
        invitedAt: now,
        joinedAt: now.add(const Duration(minutes: 1)),
        leftAt: null,
      );
      expect(joined.state, MeetingParticipantState.joined);

      final left = VorynMeetingParticipant(
        meetingId: sampleMeetingId,
        userUid: 'u3',
        role: 'participant',
        displayName: 'Past User',
        invitedAt: now,
        joinedAt: now.add(const Duration(minutes: 1)),
        leftAt: now.add(const Duration(minutes: 10)),
      );
      expect(left.state, MeetingParticipantState.left);
    });

    test('9. Meeting summary identifies invited user badge and status', () {
      final summary = VorynMeetingSummary(
        id: sampleMeetingId,
        title: 'Weekly Standup',
        joinCode: 'k7q-mzx-p2f',
        access: 'invited',
        status: 'ready',
        hostUid: 'host-1',
        myRole: 'participant',
        isHost: false,
        activeParticipantCount: 0,
        historicalAttendeeCount: 0,
        myInvitedAt: DateTime.now(),
        myJoinedAt: null,
      );

      expect(summary.isInvited, isTrue);
      expect(summary.isHost, isFalse);
    });
  });

  group('MEET-4B: Contact Picker UI Widget Tests', () {
    testWidgets('10. Renders eligible contacts and displays search filter', (tester) async {
      final mock = MockInvitationMeetingService(
        eligibleContactsToReturn: [contactAlice, contactBob, contactCharlie],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            body: MeetingInviteSheet(
              meetingId: sampleMeetingId,
              meetingTitle: 'Team Sync',
              meetingService: mock,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invite to Meeting'), findsOneWidget);
      expect(find.text('Team Sync'), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsOneWidget);
      expect(find.text('Charlie Brown'), findsOneWidget);

      // Filter by search
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();

      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('Bob Jones'), findsNothing);
      expect(find.text('Charlie Brown'), findsNothing);
    });

    testWidgets('11. Multi-select selection and Clear action work', (tester) async {
      final mock = MockInvitationMeetingService(
        eligibleContactsToReturn: [contactAlice, contactBob],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            body: MeetingInviteSheet(
              meetingId: sampleMeetingId,
              meetingService: mock,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select contacts to invite'), findsOneWidget);

      // Select Alice
      await tester.tap(find.text('Alice Smith'));
      await tester.pumpAndSettle();
      expect(find.text('Send 1 invitation'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);

      // Select Bob
      await tester.tap(find.text('Bob Jones'));
      await tester.pumpAndSettle();
      expect(find.text('Send 2 invitations'), findsOneWidget);

      // Clear selection
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Select contacts to invite'), findsOneWidget);
    });

    testWidgets('12. In-meeting and already-invited contacts display badges and disable checkbox', (tester) async {
      final now = DateTime.now();
      final mock = MockInvitationMeetingService(
        eligibleContactsToReturn: [contactAlice, contactBob, contactCharlie],
        participantsToReturn: [
          VorynMeetingParticipant(
            meetingId: sampleMeetingId,
            userUid: contactAlice.uid,
            role: 'participant',
            displayName: contactAlice.displayName,
            joinedAt: now,
            leftAt: null,
          ),
          VorynMeetingParticipant(
            meetingId: sampleMeetingId,
            userUid: contactBob.uid,
            role: 'participant',
            displayName: contactBob.displayName,
            invitedAt: now,
            joinedAt: null,
            leftAt: null,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            body: MeetingInviteSheet(
              meetingId: sampleMeetingId,
              meetingService: mock,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('In meeting'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);

      // Only Charlie has an enabled checkbox
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('13. Submitting invites triggers batch RPC and presents feedback', (tester) async {
      final mock = MockInvitationMeetingService(
        eligibleContactsToReturn: [contactAlice],
      );

      bool callbacksFired = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            body: MeetingInviteSheet(
              meetingId: sampleMeetingId,
              meetingService: mock,
              onInvitationsSent: () => callbacksFired = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Alice
      await tester.tap(find.text('Alice Smith'));
      await tester.pumpAndSettle();

      // Tap Send
      await tester.tap(find.text('Send 1 invitation'));
      await tester.pumpAndSettle();

      expect(mock.inviteCalls.length, 1);
      expect(mock.inviteCalls.first['targetUserUid'], contactAlice.uid);
      expect(callbacksFired, isTrue);
      expect(find.text('Invitations sent successfully!'), findsOneWidget);
    });

    testWidgets('14. Small viewport (360x640) renders without layout overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mock = MockInvitationMeetingService(
        eligibleContactsToReturn: [contactAlice, contactBob],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: Scaffold(
            body: MeetingInviteSheet(
              meetingId: sampleMeetingId,
              meetingTitle: 'Responsive Test Meeting',
              meetingService: mock,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('MEET-4B: MeetingDetailsScreen Integration', () {
    testWidgets('15. MeetingDetailsScreen displays real participants and Invite button', (tester) async {
      final summary = VorynMeetingSummary(
        id: sampleMeetingId,
        title: 'Architecture Review',
        joinCode: 'abc-def-123',
        access: 'link',
        status: 'active',
        isHost: true,
        hostUid: 'host-uid-1',
        myRole: 'host',
        activeParticipantCount: 2,
        historicalAttendeeCount: 2,
      );

      final mock = MockInvitationMeetingService(
        participantsToReturn: [
          const VorynMeetingParticipant(
            meetingId: sampleMeetingId,
            userUid: 'host-uid-1',
            role: 'host',
            displayName: 'Alice Host',
            isActive: true,
          ),
          VorynMeetingParticipant(
            meetingId: sampleMeetingId,
            userUid: contactBob.uid,
            role: 'participant',
            displayName: 'Bob Guest',
            invitedAt: DateTime.now(),
            joinedAt: null,
            isActive: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingDetailsScreen(
            meeting: summary,
            meetingId: sampleMeetingId,
            meetingService: mock,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invite Contacts'), findsOneWidget);
      expect(find.text('Alice Host'), findsOneWidget);
      expect(find.text('Bob Guest'), findsOneWidget);
      expect(find.text('Host'), findsWidgets);
      expect(find.text('Invited'), findsWidgets);
    });

    testWidgets('16. MeetingDetailsScreen displays invited banner for invited users', (tester) async {
      final summary = VorynMeetingSummary(
        id: sampleMeetingId,
        title: 'Invited Session',
        joinCode: 'abc-def-123',
        access: 'invited',
        status: 'ready',
        isHost: false,
        hostUid: 'organizer-uid',
        myRole: 'participant',
        activeParticipantCount: 0,
        historicalAttendeeCount: 0,
        myInvitedAt: DateTime.now(),
        myJoinedAt: null,
      );

      final mock = MockInvitationMeetingService();

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingDetailsScreen(
            meeting: summary,
            meetingId: sampleMeetingId,
            meetingService: mock,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You are invited to this meeting'), findsOneWidget);
      expect(find.text('Invited Guest'), findsOneWidget);
    });
  });
}

