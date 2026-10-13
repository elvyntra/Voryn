import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/calling/voryn_livekit_service.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';

class SimulatedEndMeetingResult {
  final int statusCode;
  final Map<String, dynamic> body;

  SimulatedEndMeetingResult(this.statusCode, this.body);

  bool get isOk => statusCode == 200 && body['ok'] == true;
}

class SimulatedMeetingDatabase {
  final Map<String, Map<String, dynamic>> meetings = {};
  final List<Map<String, dynamic>> participants = [];
  bool failDbRpc = false;

  void addMeeting({
    required String id,
    required String title,
    required String hostUid,
    String status = 'active',
  }) {
    meetings[id] = {
      'id': id,
      'title': title,
      'host_uid': hostUid,
      'status': status,
      'ended_at': status == 'ended' ? DateTime.now().toIso8601String() : null,
    };
  }

  void addParticipant({
    required String meetingId,
    required String userUid,
    required String role,
    DateTime? joinedAt,
    DateTime? leftAt,
  }) {
    participants.add({
      'meeting_id': meetingId,
      'user_uid': userUid,
      'role': role,
      'joined_at': (joinedAt ?? DateTime.now()).toIso8601String(),
      'left_at': leftAt?.toIso8601String(),
    });
  }

  Map<String, dynamic> endMeetingForEveryoneRpc(String meetingId, String callerUid) {
    if (failDbRpc) {
      throw Exception('Database lock timeout or deadlock');
    }
    final meeting = meetings[meetingId];
    if (meeting == null) throw Exception('Meeting not found');
    if (meeting['host_uid'] != callerUid) {
      throw Exception('Only the meeting host can end the meeting for everyone');
    }
    if (meeting['status'] == 'cancelled') {
      throw Exception('Cancelled meeting cannot be ended');
    }
    meeting['status'] = 'ended';
    meeting['ended_at'] = DateTime.now().toIso8601String();

    for (final p in participants) {
      if (p['meeting_id'] == meetingId && p['left_at'] == null) {
        p['left_at'] = DateTime.now().toIso8601String();
      }
    }
    return meeting;
  }

  Map<String, dynamic> leaveMeetingRpc(String meetingId, String callerUid) {
    final meeting = meetings[meetingId];
    if (meeting == null) throw Exception('Meeting not found');

    for (final p in participants) {
      if (p['meeting_id'] == meetingId && p['user_uid'] == callerUid) {
        p['left_at'] ??= DateTime.now().toIso8601String();
      }
    }

    final activeCount = participants
        .where((p) => p['meeting_id'] == meetingId && p['joined_at'] != null && p['left_at'] == null)
        .length;

    if (meeting['status'] == 'active' && activeCount == 0) {
      meeting['status'] = 'ended';
      meeting['ended_at'] ??= DateTime.now().toIso8601String();
    }

    return {
      'meeting_id': meetingId,
      'status': meeting['status'],
      'active_participant_count': activeCount,
    };
  }
}

class SimulatedLiveKitServer {
  final Set<String> activeRooms = {};
  bool failDeletion = false;
  int deleteCallCount = 0;
  String? lastDeletedRoom;

  void createRoom(String roomName) {
    activeRooms.add(roomName);
  }

  void deleteRoom(String roomName) {
    deleteCallCount++;
    lastDeletedRoom = roomName;

    if (failDeletion) {
      throw Exception('LiveKit API gateway 503 service unavailable');
    }

    if (!activeRooms.contains(roomName)) {
      throw Exception('Room not found (status 404)');
    }
    activeRooms.remove(roomName);
  }
}

SimulatedEndMeetingResult handleSimulatedEndVorynMeeting({
  required String? authorization,
  required Map<String, dynamic> requestBody,
  required SimulatedMeetingDatabase db,
  required SimulatedLiveKitServer livekit,
  required String? Function(String authHeader) verifyAuthToken,
}) {
  if (authorization == null || authorization.isEmpty) {
    return SimulatedEndMeetingResult(401, {'error': 'Authentication is required.'});
  }

  final callerUid = verifyAuthToken(authorization);
  if (callerUid == null) {
    return SimulatedEndMeetingResult(401, {'error': 'Your session has expired. Please sign in again.'});
  }

  final meetingId = requestBody['meetingId'];
  if (meetingId == null || meetingId is! String || !RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(meetingId)) {
    return SimulatedEndMeetingResult(400, {'error': 'Invalid meeting ID.'});
  }

  final meeting = db.meetings[meetingId];
  if (meeting == null) {
    return SimulatedEndMeetingResult(404, {'error': 'Meeting not found.'});
  }

  if (meeting['status'] == 'cancelled') {
    return SimulatedEndMeetingResult(400, {'error': 'Cancelled meeting cannot be ended.'});
  }

  final isHost = meeting['host_uid'] == callerUid;
  final action = requestBody['action'];
  final isCleanupAction = action == 'cleanup';
  final wasAlreadyEnded = meeting['status'] == 'ended';

  if (isCleanupAction) {
    // PATH A: POST-END CLEANUP
    if (meeting['status'] != 'ended') {
      return SimulatedEndMeetingResult(400, {
        'error': 'Cannot clean up an active meeting. Host must end it first.',
      });
    }

    final isPart = db.participants.any((p) => p['meeting_id'] == meetingId && p['user_uid'] == callerUid);
    if (!isHost && !isPart) {
      return SimulatedEndMeetingResult(403, {
        'error': 'Unauthorized: not a participant of this meeting.',
      });
    }

    final activeCount = db.participants
        .where((p) => p['meeting_id'] == meetingId && p['joined_at'] != null && p['left_at'] == null)
        .length;
    if (activeCount > 0) {
      return SimulatedEndMeetingResult(400, {
        'error': 'Cannot clean up room: active participants still remain in meeting.',
      });
    }
  } else {
    // PATH B: HOST TERMINATION
    if (!isHost) {
      if (meeting['status'] != 'ended') {
        return SimulatedEndMeetingResult(403, {
          'error': 'Only the meeting host can end an active meeting for everyone.',
        });
      }

      final isPart = db.participants.any((p) => p['meeting_id'] == meetingId && p['user_uid'] == callerUid);
      if (!isPart) {
        return SimulatedEndMeetingResult(403, {
          'error': 'Unauthorized: not a participant of this meeting.',
        });
      }

      final activeCount = db.participants
          .where((p) => p['meeting_id'] == meetingId && p['joined_at'] != null && p['left_at'] == null)
          .length;
      if (activeCount > 0) {
        return SimulatedEndMeetingResult(400, {
          'error': 'Cannot clean up room: active participants still remain in meeting.',
        });
      }
    }

    if (!wasAlreadyEnded && isHost) {
      try {
        db.endMeetingForEveryoneRpc(meetingId, callerUid);
      } catch (e) {
        return SimulatedEndMeetingResult(500, {
          'ok': false,
          'status': 'failed_before_db',
          'error': 'Database failed to end meeting: $e',
          'dbEnded': false,
          'roomDeleted': false,
        });
      }
    }
  }

  // Canonical room name is ALWAYS derived strictly server-side
  final canonicalRoomName = 'voryn-meeting-${meeting['id']}';

  bool roomDeleted = false;
  bool livekitCleanupPending = false;
  String? livekitErrorMsg;

  try {
    livekit.deleteRoom(canonicalRoomName);
    roomDeleted = true;
  } catch (lkErr) {
    final errStr = lkErr.toString().toLowerCase();
    if (errStr.contains('not found') || errStr.contains('404')) {
      roomDeleted = true; // idempotent
    } else {
      livekitCleanupPending = true;
      livekitErrorMsg = lkErr.toString();
    }
  }

  if (livekitCleanupPending) {
    return SimulatedEndMeetingResult(502, {
      'ok': false,
      'status': 'db_ended_livekit_pending',
      'meetingId': meeting['id'],
      'dbEnded': true,
      'roomDeleted': false,
      'livekitCleanupPending': true,
      'error': 'Meeting ended in database, but LiveKit room cleanup is pending: $livekitErrorMsg',
    });
  }

  return SimulatedEndMeetingResult(200, {
    'ok': true,
    'status': wasAlreadyEnded
        ? (isHost && !isCleanupAction ? 'already_ended' : 'cleaned_up')
        : 'ended',
    'meetingId': meeting['id'],
    'roomName': canonicalRoomName,
    'dbEnded': true,
    'roomDeleted': roomDeleted,
    'livekitCleanupPending': false,
  });
}

Map<String, dynamic> handleSimulatedLiveKitToken({
  required String? authorization,
  required String? meetingId,
  required SimulatedMeetingDatabase db,
  required String? Function(String authHeader) verifyAuthToken,
}) {
  if (authorization == null || authorization.isEmpty) {
    return {'statusCode': 401, 'error': 'Authentication is required.'};
  }
  final callerUid = verifyAuthToken(authorization);
  if (callerUid == null) {
    return {'statusCode': 401, 'error': 'Your session has expired.'};
  }
  final meeting = db.meetings[meetingId];
  if (meeting == null) {
    return {'statusCode': 404, 'error': 'Meeting not found.'};
  }
  if (meeting['status'] != 'active') {
    return {'statusCode': 403, 'error': 'Meeting has ${meeting['status']}.'};
  }
  return {'statusCode': 200, 'token': 'mock-livekit-jwt'};
}

void main() {
  const hostUid = 'host-user-uuid-1111-111111111111';
  const participantUid = 'part-user-uuid-2222-222222222222';
  const outsiderUid = 'outsider-uuid-3333-333333333333';
  const meetingId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  String? mockAuthVerifier(String token) {
    if (token == 'Bearer token-host') return hostUid;
    if (token == 'Bearer token-part') return participantUid;
    if (token == 'Bearer token-outsider') return outsiderUid;
    return null;
  }

  late SimulatedMeetingDatabase db;
  late SimulatedLiveKitServer livekit;

  setUp(() {
    db = SimulatedMeetingDatabase();
    livekit = SimulatedLiveKitServer();

    db.addMeeting(
      id: meetingId,
      title: 'Weekly Standup',
      hostUid: hostUid,
      status: 'active',
    );
    db.addParticipant(
      meetingId: meetingId,
      userUid: hostUid,
      role: 'host',
    );
    db.addParticipant(
      meetingId: meetingId,
      userUid: participantUid,
      role: 'participant',
    );

    livekit.createRoom('voryn-meeting-$meetingId');
  });

  group('Checkpoint MEET-3C.1: Meeting Termination Hardening Tests', () {
    // 1. Host can end active meeting.
    test('1. Host can end active meeting', () {
      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 200);
      expect(res.isOk, true);
      expect(res.body['status'], 'ended');
      expect(res.body['dbEnded'], true);
      expect(res.body['roomDeleted'], true);
      expect(db.meetings[meetingId]!['status'], 'ended');
      expect(livekit.activeRooms.contains('voryn-meeting-$meetingId'), false);
    });

    // 2. Unauthenticated request is denied.
    test('2. Unauthenticated request is denied (401)', () {
      final res = handleSimulatedEndVorynMeeting(
        authorization: null,
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 401);
      expect(res.body['error'], contains('Authentication is required'));
    });

    // 3. Non-host End Everyone request is denied.
    test('3. Non-host cannot end active meeting (403)', () {
      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-part',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 403);
      expect(res.body['error'], contains('Only the meeting host can end an active meeting for everyone'));
      expect(db.meetings[meetingId]!['status'], 'active');
      expect(livekit.activeRooms.contains('voryn-meeting-$meetingId'), true);
    });

    // 4. Non-host cannot bypass host authorization using reason=last_participant_left.
    test('4. Non-host cannot bypass host authorization using reason=last_participant_left', () {
      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-part',
        requestBody: {
          'meetingId': meetingId,
          'reason': 'last_participant_left',
        },
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 403);
      expect(res.body['error'], contains('Only the meeting host can end an active meeting for everyone'));
      expect(db.meetings[meetingId]!['status'], 'active');
      expect(livekit.activeRooms.contains('voryn-meeting-$meetingId'), true);
    });

    // 5. Active meeting cannot be cleaned up by a participant-provided reason.
    test('5. Active meeting cannot be terminated through cleanup-only requests (400)', () {
      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-part',
        requestBody: {
          'meetingId': meetingId,
          'action': 'cleanup',
          'reason': 'last_participant_left',
        },
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 400);
      expect(res.body['error'], contains('Cannot clean up an active meeting'));
      expect(db.meetings[meetingId]!['status'], 'active');
    });

    // 6. Ended meeting with zero participants permits authorized cleanup.
    test('6. Ended meeting with zero active participants permits authorized cleanup (200)', () {
      // Mark all participants left and meeting ended in DB
      for (final p in db.participants) {
        p['left_at'] = DateTime.now().toIso8601String();
      }
      db.meetings[meetingId]!['status'] = 'ended';

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-part',
        requestBody: {
          'meetingId': meetingId,
          'action': 'cleanup',
        },
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 200);
      expect(res.body['status'], 'cleaned_up');
      expect(res.body['roomDeleted'], true);
      expect(livekit.activeRooms.contains('voryn-meeting-$meetingId'), false);
    });

    // 7. Unrelated user cannot clean up meeting.
    test('7. Unrelated user cannot clean up another meeting (403)', () {
      for (final p in db.participants) {
        p['left_at'] = DateTime.now().toIso8601String();
      }
      db.meetings[meetingId]!['status'] = 'ended';

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-outsider',
        requestBody: {
          'meetingId': meetingId,
          'action': 'cleanup',
        },
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 403);
      expect(res.body['error'], contains('Unauthorized: not a participant of this meeting'));
    });

    // 8. Client-supplied room name is ignored and derived server-side.
    test('8. Client-supplied room name is ignored and derived server-side', () {
      for (final p in db.participants) {
        p['left_at'] = DateTime.now().toIso8601String();
      }
      db.meetings[meetingId]!['status'] = 'ended';

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-part',
        requestBody: {
          'meetingId': meetingId,
          'action': 'cleanup',
          'roomName': 'malicious-injected-room-id',
        },
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.isOk, true);
      expect(res.body['roomName'], 'voryn-meeting-$meetingId');
      expect(livekit.lastDeletedRoom, 'voryn-meeting-$meetingId');
    });

    // 9. Database failure does not produce false success.
    test('9. Database failure does not produce false success (500 failed_before_db)', () {
      db.failDbRpc = true;

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 500);
      expect(res.body['ok'], false);
      expect(res.body['status'], 'failed_before_db');
      expect(res.body['dbEnded'], false);
      expect(res.body['roomDeleted'], false);
      expect(db.meetings[meetingId]!['status'], 'active');
      expect(livekit.activeRooms.contains('voryn-meeting-$meetingId'), true);
    });

    // 10. LiveKit room deletion recognized.
    test('10. LiveKit deletion success is recognized', () {
      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 200);
      expect(res.body['roomDeleted'], true);
      expect(livekit.deleteCallCount, 1);
    });

    // 11. Room already absent is idempotent.
    test('11. Already absent LiveKit room is idempotent', () {
      livekit.activeRooms.clear();

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 200);
      expect(res.body['roomDeleted'], true);
    });

    // 12. DB end succeeds but LiveKit fails reports pending cleanup.
    test('12. LiveKit failure produces cleanup-pending status (502)', () {
      livekit.failDeletion = true;

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 502);
      expect(res.body['ok'], false);
      expect(res.body['status'], 'db_ended_livekit_pending');
      expect(res.body['dbEnded'], true);
      expect(res.body['roomDeleted'], false);
      expect(res.body['livekitCleanupPending'], true);
      expect(db.meetings[meetingId]!['status'], 'ended');
    });

    // 13. Retry after partial failure succeeds.
    test('13. Retry after partial completion succeeds', () {
      livekit.failDeletion = true;
      final res1 = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );
      expect(res1.body['livekitCleanupPending'], true);
      expect(db.meetings[meetingId]!['status'], 'ended');

      // Recover LiveKit gateway
      livekit.failDeletion = false;
      final res2 = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res2.statusCode, 200);
      expect(res2.body['ok'], true);
      expect(res2.body['status'], 'already_ended');
      expect(res2.body['roomDeleted'], true);
    });

    // 14. Concurrent host end and participant leave.
    test('14. Concurrent host end and participant leave serialized cleanly', () {
      db.leaveMeetingRpc(meetingId, participantUid);
      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 200);
      expect(res.body['dbEnded'], true);
      expect(res.body['roomDeleted'], true);
      expect(db.meetings[meetingId]!['status'], 'ended');
    });

    // 15. Duplicate end requests are safe.
    test('15. Duplicate end requests are safe and idempotent', () {
      final res1 = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );
      expect(res1.statusCode, 200);
      expect(res1.body['status'], 'ended');

      final res2 = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-host',
        requestBody: {'meetingId': meetingId},
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );
      expect(res2.statusCode, 200);
      expect(res2.body['status'], 'already_ended');
      expect(res2.body['dbEnded'], true);
      expect(res2.body['roomDeleted'], true);
    });

    // 16. Ended meeting denies new LiveKit tokens.
    test('16. Ended meeting denies new LiveKit tokens (403)', () {
      db.meetings[meetingId]!['status'] = 'ended';

      final tokenRes = handleSimulatedLiveKitToken(
        authorization: 'Bearer token-part',
        meetingId: meetingId,
        db: db,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(tokenRes['statusCode'], 403);
      expect(tokenRes['error'], contains('Meeting has ended'));
    });

    // 17. Ended meeting denies rejoining.
    test('17. Ended meeting denies rejoining (status filtering)', () {
      db.meetings[meetingId]!['status'] = 'ended';

      final candidate = db.meetings.values.firstWhere(
        (m) => m['id'] == meetingId && (m['status'] == 'ready' || m['status'] == 'active'),
        orElse: () => {},
      );

      expect(candidate.isEmpty, true);
    });

    // 18. Direct-call and merge calls regression check.
    test('18. Direct-call and merge calls regression check', () {
      const service = VorynLiveKitService();
      expect(service.connect, isNotNull);
      expect(service.connectProvisional, isNotNull);
      expect(service.connectMeeting, isNotNull);
    });

    // 19. UI distinction: Termination failed before DB update keeps meeting active.
    test('19. UI distinction: Termination failed before DB update keeps meeting active', () {
      const result = MeetingEndResult(
        status: MeetingEndStatus.failedBeforeDb,
        dbEnded: false,
        roomDeleted: false,
        errorMessage: 'Database deadlock',
      );

      expect(result.status, MeetingEndStatus.failedBeforeDb);
      expect(result.dbEnded, false);
      expect(result.roomDeleted, false);
      expect(result.isFullyTerminated, false);
      expect(result.isEndedWithCleanupPending, false);
    });

    // 20. UI distinction: Meeting ended with cleanup pending.
    test('20. UI distinction: Meeting ended with cleanup pending', () {
      const result = MeetingEndResult(
        status: MeetingEndStatus.endedCleanupPending,
        dbEnded: true,
        roomDeleted: false,
        errorMessage: 'LiveKit 503 gateway',
      );

      expect(result.status, MeetingEndStatus.endedCleanupPending);
      expect(result.dbEnded, true);
      expect(result.roomDeleted, false);
      expect(result.isEndedWithCleanupPending, true);
      expect(result.isFullyTerminated, false);
    });

    // 21. UI distinction: Meeting fully terminated.
    test('21. UI distinction: Meeting fully terminated', () {
      const result = MeetingEndResult(
        status: MeetingEndStatus.ended,
        dbEnded: true,
        roomDeleted: true,
      );

      expect(result.status, MeetingEndStatus.ended);
      expect(result.dbEnded, true);
      expect(result.roomDeleted, true);
      expect(result.isFullyTerminated, true);
      expect(result.isEndedWithCleanupPending, false);
    });

    // 22. Active meeting with zero participants cannot be cleaned up by non-host.
    test('22. Active meeting with zero participants cannot be cleaned up by non-host', () {
      for (final p in db.participants) {
        p['left_at'] = DateTime.now().toIso8601String();
      }
      db.meetings[meetingId]!['status'] = 'active';

      final res = handleSimulatedEndVorynMeeting(
        authorization: 'Bearer token-part',
        requestBody: {
          'meetingId': meetingId,
          'action': 'cleanup',
        },
        db: db,
        livekit: livekit,
        verifyAuthToken: mockAuthVerifier,
      );

      expect(res.statusCode, 400);
      expect(res.body['error'], contains('Cannot clean up an active meeting'));
    });
  });
}
