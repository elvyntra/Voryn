import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';

class MockVorynMeetingServiceForJoin extends VorynMeetingService {
  MockVorynMeetingServiceForJoin({
    this.joinDelay = Duration.zero,
    this.shouldThrow = false,
    this.throwException,
    this.joinedMeetingToReturn,
  });

  final Duration joinDelay;
  final bool shouldThrow;
  final Object? throwException;
  final VorynJoinedMeeting? joinedMeetingToReturn;

  int joinCallCount = 0;
  String? lastCode;

  @override
  Future<VorynJoinedMeeting> joinMeeting(
    String rawCode, {
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    final normalized = normalizeMeetingJoinCode(rawCode);
    if (normalized == null) {
      throw ArgumentError('Invalid meeting code format');
    }

    joinCallCount++;
    lastCode = normalized;

    if (joinDelay > Duration.zero) {
      await Future<void>.delayed(joinDelay);
    }

    if (shouldThrow) {
      throw throwException ?? Exception('PGRST202: Could not find function');
    }

    return joinedMeetingToReturn ??
        VorynJoinedMeeting(
          meetingId: 'meet-uuid-join-123',
          title: 'Engineering Sync',
          livekitRoomName: 'voryn-meeting-meet-uuid-join-123',
          role: 'participant',
          status: 'ready',
          access: 'link',
          joinCode: normalized,
          livekitToken: 'mock-livekit-token',
          livekitUrl: 'wss://livekit.test',
          initialMic: initialMic,
          initialCamera: initialCamera,
        );
  }
}

void main() {
  group('Part A — Meeting Join Verification Tests', () {
    test('VorynJoinedMeeting.fromJson correctly extracts meetingId from "id" or "meeting_id"', () {
      // Deployed SQL returns `id`
      final jsonFromRpc = {
        'id': 'join-uuid-999',
        'title': 'Design Review',
        'join_code': 'abc-def-ghi',
        'access': 'link',
        'status': 'ready',
        'role': 'participant',
      };
      final m1 = VorynJoinedMeeting.fromJson(
        jsonFromRpc,
        livekitToken: 'token-123',
        livekitUrl: 'wss://test.url',
      );
      expect(m1.meetingId, 'join-uuid-999');
      expect(m1.title, 'Design Review');
      expect(m1.joinCode, 'abc-def-ghi');
      expect(m1.livekitRoomName, 'voryn-meeting-join-uuid-999');
      expect(m1.livekitToken, 'token-123');

      // Alternative schema with `meeting_id` and explicit `livekit_room_name`
      final jsonWithMeetingId = {
        'meeting_id': 'join-uuid-888',
        'title': 'All Hands',
        'join_code': 'xyz-uvw-rst',
        'access': 'invited',
        'status': 'active',
        'role': 'host',
        'livekit_room_name': 'custom-room-xyz',
      };
      final m2 = VorynJoinedMeeting.fromJson(jsonWithMeetingId);
      expect(m2.meetingId, 'join-uuid-888');
      expect(m2.title, 'All Hands');
      expect(m2.livekitRoomName, 'custom-room-xyz');
      expect(m2.isHost, isTrue);
    });

    test('normalizeMeetingJoinCode properly formats join codes', () {
      expect(normalizeMeetingJoinCode('abc def ghi'), 'abc-def-ghi');
      expect(normalizeMeetingJoinCode('ABC-DEF-GHI'), 'abc-def-ghi');
      expect(normalizeMeetingJoinCode('https://voryn.app/meet/abc-def-ghi'), 'abc-def-ghi');
      expect(normalizeMeetingJoinCode('invalid'), isNull);
    });

    test('Mock join service validates join codes', () async {
      final mock = MockVorynMeetingServiceForJoin();
      expect(() => mock.joinMeeting('invalid-code'), throwsA(isA<ArgumentError>()));

      final res = await mock.joinMeeting('abc-def-ghi');
      expect(res.meetingId, 'meet-uuid-join-123');
      expect(res.joinCode, 'abc-def-ghi');
      expect(mock.joinCallCount, 1);
    });
  });
}

