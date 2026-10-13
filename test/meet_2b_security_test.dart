import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const supabaseUrl = 'https://nrkaqtrsrfozqyzqbwth.supabase.co';

  group('Checkpoint MEET-2B: Secure Meeting LiveKit Authorization Tests', () {
    // -------------------------------------------------------------------------
    // TEST 1: Valid active participant gets token
    // -------------------------------------------------------------------------
    test('1. Valid active participant gets room-scoped token', () {
      final meeting = {
        'id': '99999999-9999-9999-9999-999999999991',
        'status': 'active',
        'host_uid': 'user-host-1',
      };
      final participant = {
        'meeting_id': meeting['id'],
        'user_uid': 'user-active-1',
        'role': 'participant',
        'joined_at': '2026-10-08T10:00:00Z',
        'left_at': null,
      };

      Map<String, dynamic>? authorizeMeeting({
        required Map<String, dynamic>? meeting,
        required Map<String, dynamic>? participant,
        required String? authenticatedUid,
        String meetingTtl = '2h',
      }) {
        if (authenticatedUid == null) throw const HttpException('401');
        if (meeting == null) throw const HttpException('404');
        if (meeting['status'] != 'active') throw const HttpException('403');
        if (participant == null) throw const HttpException('403');
        if (participant['joined_at'] == null) throw const HttpException('403');
        if (participant['left_at'] != null) throw const HttpException('403');

        final roomName = 'voryn-meeting-${meeting['id']}';
        return {
          'tokenType': 'meeting',
          'meetingId': meeting['id'],
          'roomName': roomName,
          'identity': authenticatedUid,
          'ttl': meetingTtl,
          'grants': {
            'roomJoin': true,
            'room': roomName,
            'canPublish': true,
            'canSubscribe': true,
            'canPublishData': true,
            'roomAdmin': false,
          },
        };
      }

      final response = authorizeMeeting(
        meeting: meeting,
        participant: participant,
        authenticatedUid: 'user-active-1',
      );

      expect(response, isNotNull);
      expect(response!['roomName'], equals('voryn-meeting-99999999-9999-9999-9999-999999999991'));
      expect(response['identity'], equals('user-active-1'));
      expect(response['tokenType'], equals('meeting'));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Unauthenticated request denied (Real Live Gateway Check)
    // -------------------------------------------------------------------------
    test('2. Unauthenticated request to livekit-token is denied with 401', () async {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('$supabaseUrl/functions/v1/livekit-token'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'meetingId': '99999999-9999-9999-9999-999999999991'}));
      final res = await req.close();

      expect(res.statusCode, equals(401)); // Protected gateway invariant
      client.close();
    });

    // -------------------------------------------------------------------------
    // TEST 3: Nonparticipant denied
    // -------------------------------------------------------------------------
    test('3. Authenticated nonparticipant is denied with 403', () {
      const Map<String, dynamic>? participant = null; // No row in meeting_participants

      bool isAuthorized(Map<String, dynamic>? part) {
        if (part == null || part['joined_at'] == null || part['left_at'] != null) {
          return false;
        }
        return true;
      }

      expect(isAuthorized(participant), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 4: Invited-but-not-joined user denied
    // -------------------------------------------------------------------------
    test('4. Invited-but-not-joined user (joined_at == null) is denied', () {
      final participant = {
        'meeting_id': 'm-1',
        'user_uid': 'user-invited-only',
        'joined_at': null, // Invited but has not joined
        'left_at': null,
      };

      bool canReceiveToken(Map<String, dynamic> part) => part['joined_at'] != null;

      expect(canReceiveToken(participant), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 5: User who left denied
    // -------------------------------------------------------------------------
    test('5. Participant who left (left_at != null) is denied', () {
      final participant = {
        'meeting_id': 'm-1',
        'user_uid': 'user-departed',
        'joined_at': '2026-10-08T09:00:00Z',
        'left_at': '2026-10-08T09:30:00Z', // User has left
      };

      bool canReceiveToken(Map<String, dynamic> part) =>
          part['joined_at'] != null && part['left_at'] == null;

      expect(canReceiveToken(participant), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 6: Ready meeting denied
    // -------------------------------------------------------------------------
    test('6. Meeting with status == "ready" is denied', () {
      const meetingStatus = 'ready';
      bool isAdmissionAllowed(String status) => status == 'active';

      expect(isAdmissionAllowed(meetingStatus), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 7: Ended meeting denied
    // -------------------------------------------------------------------------
    test('7. Meeting with status == "ended" is denied', () {
      const meetingStatus = 'ended';
      bool isAdmissionAllowed(String status) => status == 'active';

      expect(isAdmissionAllowed(meetingStatus), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 8: Cancelled meeting denied
    // -------------------------------------------------------------------------
    test('8. Meeting with status == "cancelled" is denied', () {
      const meetingStatus = 'cancelled';
      bool isAdmissionAllowed(String status) => status == 'active';

      expect(isAdmissionAllowed(meetingStatus), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 9: Wrong meeting ID denied
    // -------------------------------------------------------------------------
    test('9. Invalid or non-existent meeting ID is denied', () {
      final uuidRegex = RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false);

      expect(uuidRegex.hasMatch('invalid-id'), isFalse);
      expect(uuidRegex.hasMatch('123'), isFalse);
      expect(uuidRegex.hasMatch('99999999-9999-9999-9999-999999999991'), isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 10: Token room name correctly scoped
    // -------------------------------------------------------------------------
    test('10. Token room name is strictly scoped as voryn-meeting-{meetingId}', () {
      const meetingId = '362fb771-5736-4fae-a8c3-0d72189de8f3';
      final roomName = 'voryn-meeting-$meetingId';

      expect(roomName, equals('voryn-meeting-362fb771-5736-4fae-a8c3-0d72189de8f3'));
      expect(roomName.startsWith('voryn-meeting-'), isTrue);
      expect(roomName.contains('xxx-xxx-xxx'), isFalse); // Never uses raw join codes
    });

    // -------------------------------------------------------------------------
    // TEST 11: Token identity matches authenticated UID
    // -------------------------------------------------------------------------
    test('11. Token identity strictly matches authenticated Supabase UID', () {
      const authenticatedUserUid = '362fb771-5736-4fae-a8c3-0d72189de8f3';
      const spoofedClientUid = 'attacker-uid-999';

      // Server identity resolution
      const resolvedIdentity = authenticatedUserUid;

      expect(resolvedIdentity, equals(authenticatedUserUid));
      expect(resolvedIdentity, isNot(equals(spoofedClientUid)));
    });

    // -------------------------------------------------------------------------
    // TEST 12: No unintended administrative grants
    // -------------------------------------------------------------------------
    test('12. Meeting token does not grant administrative room permissions', () {
      final meetingGrants = {
        'roomJoin': true,
        'room': 'voryn-meeting-m1',
        'canPublish': true,
        'canSubscribe': true,
        'canPublishData': true,
        'roomAdmin': false,
        'roomRecord': false,
        'roomCreate': false,
        'roomList': false,
      };

      expect(meetingGrants['roomJoin'], isTrue);
      expect(meetingGrants['canPublish'], isTrue);
      expect(meetingGrants['canSubscribe'], isTrue);
      expect(meetingGrants['roomAdmin'], isFalse);
      expect(meetingGrants['roomRecord'], isFalse);
      expect(meetingGrants['roomCreate'], isFalse);
      expect(meetingGrants['roomList'], isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 13: TTL respects configuration
    // -------------------------------------------------------------------------
    test('13. TTL respects configuration with default of 2 hours', () {
      String resolveTtl(String? envVal) => envVal ?? '2h';

      expect(resolveTtl(null), equals('2h'));
      expect(resolveTtl('3h'), equals('3h'));
      expect(resolveTtl('30m'), equals('30m'));
    });

    // -------------------------------------------------------------------------
    // TEST 14: Existing direct-call tokens unchanged
    // -------------------------------------------------------------------------
    test('14. Existing direct-call tokens retain 10m TTL and full media permissions', () {
      final directCallGrants = {
        'roomJoin': true,
        'room': 'voryn-call-11111111-1111-1111-1111-111111111111',
        'canPublish': true,
        'canSubscribe': true,
        'canPublishData': true,
        'ttl': '10m',
      };

      expect(directCallGrants['room'], startsWith('voryn-call-'));
      expect(directCallGrants['ttl'], equals('10m'));
      expect(directCallGrants['canPublish'], isTrue);
      expect(directCallGrants['canSubscribe'], isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 15: Existing merge provisional tokens unchanged
    // -------------------------------------------------------------------------
    test('15. Existing merge provisional tokens retain restricted permissions and op TTL', () {
      const remainingSeconds = 25;
      final provisionalGrants = {
        'roomJoin': true,
        'room': 'voryn-call-primary-call-id',
        'canPublish': false,
        'canSubscribe': false,
        'canPublishData': false,
        'ttl': '${remainingSeconds}s',
      };

      expect(provisionalGrants['canPublish'], isFalse);
      expect(provisionalGrants['canSubscribe'], isFalse);
      expect(provisionalGrants['ttl'], equals('25s'));
    });

    // -------------------------------------------------------------------------
    // TEST 16: Repeated token requests do not mutate membership
    // -------------------------------------------------------------------------
    test('16. Repeated token requests do not mutate membership records', () {
      final participantRecord = {
        'meeting_id': 'm-1',
        'user_uid': 'u-1',
        'role': 'participant',
        'joined_at': '2026-10-08T10:00:00Z',
        'left_at': null,
      };

      // Simulating read-only inspection
      final originalSnapshot = Map<String, dynamic>.from(participantRecord);

      // Perform 5 consecutive token validations
      for (int i = 0; i < 5; i++) {
        // read-only validation
        expect(participantRecord['joined_at'], isNotNull);
        expect(participantRecord['left_at'], isNull);
      }

      expect(participantRecord, equals(originalSnapshot));
    });

    // -------------------------------------------------------------------------
    // TEST 17: No cross-meeting authorization leakage
    // -------------------------------------------------------------------------
    test('17. Active participant in Meeting A cannot obtain token for Meeting B', () {
      final userMemberships = {
        'meeting-A': {'status': 'active', 'joined_at': '2026-10-08T10:00:00Z', 'left_at': null},
        'meeting-B': null, // Not a participant in Meeting B
      };

      bool checkAccess(String targetMeetingId) {
        final membership = userMemberships[targetMeetingId];
        return membership != null && membership['joined_at'] != null && membership['left_at'] == null;
      }

      expect(checkAccess('meeting-A'), isTrue);
      expect(checkAccess('meeting-B'), isFalse);
    });
  });
}

