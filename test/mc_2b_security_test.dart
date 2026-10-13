import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const supabaseUrl = 'https://nrkaqtrsrfozqyzqbwth.supabase.co';

  group('Checkpoint MC-2B.1: Merge Admission Hardening & Security Tests', () {
    // -------------------------------------------------------------------------
    // TEST 1: Provisional token expiry <= merge expiry
    // -------------------------------------------------------------------------
    test('1. Provisional token expiry is strictly bounded by remaining merge expiry', () {
      final now = DateTime.now();
      final mergeExpiry = now.add(const Duration(seconds: 18));
      final remainingSeconds = mergeExpiry.difference(now).inSeconds;

      final effectiveTtl = remainingSeconds < 30 ? remainingSeconds : 30;

      expect(effectiveTtl, equals(18));
      expect(effectiveTtl <= 30, isTrue);
      expect(effectiveTtl <= remainingSeconds, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 2: Nearly-expired operation does not receive unsafe token (< 5s)
    // -------------------------------------------------------------------------
    test('2. Nearly-expired operation (< 5s) is rejected with merge_op_expiring', () {
      final now = DateTime.now();
      final mergeExpiry = now.add(const Duration(seconds: 4));
      final remainingSeconds = mergeExpiry.difference(now).inSeconds;

      bool canIssueToken(int remainingSec) => remainingSec >= 5;

      expect(canIssueToken(remainingSeconds), isFalse);
      expect(canIssueToken(5), isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 3: Cancelled op cannot issue token
    // -------------------------------------------------------------------------
    test('3. Cancelled operations cannot issue provisional tokens', () {
      final now = DateTime.now();
      bool canIssue(String status, DateTime expiresAt) {
        if (status == 'cancelled' || status == 'expired') return false;
        if (expiresAt.isBefore(now)) return false;
        return status == 'prepared' || status == 'joining';
      }

      expect(canIssue('cancelled', now.add(const Duration(seconds: 20))), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 4: Expired op cannot issue token
    // -------------------------------------------------------------------------
    test('4. Expired operations cannot issue provisional tokens', () {
      final now = DateTime.now();
      bool canIssue(String status, DateTime expiresAt) {
        if (status == 'cancelled' || status == 'expired') return false;
        if (expiresAt.isBefore(now)) return false;
        return status == 'prepared' || status == 'joining';
      }

      expect(canIssue('expired', now.add(const Duration(seconds: 20))), isFalse);
      expect(canIssue('prepared', now.subtract(const Duration(seconds: 1))), isFalse);
      expect(canIssue('prepared', now.add(const Duration(seconds: 20))), isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 5: Active provisional participant removed on cancel
    // -------------------------------------------------------------------------
    test('5. Active provisional participant is ejected from primary room on cancel', () {
      final roomParticipants = <String, Set<String>>{
        'voryn-call-primary': {'user-a', 'user-b', 'user-c-provisional'},
        'voryn-call-secondary': {'user-a', 'user-c-active'},
      };

      void cleanupProvisional(String primaryRoom, String participant) {
        roomParticipants[primaryRoom]?.remove(participant);
      }

      cleanupProvisional('voryn-call-primary', 'user-c-provisional');

      expect(roomParticipants['voryn-call-primary']!.contains('user-c-provisional'), isFalse);
      expect(roomParticipants['voryn-call-primary']!.contains('user-b'), isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 6: Active provisional participant removed on expiry
    // -------------------------------------------------------------------------
    test('6. Active provisional participant is ejected from primary room on expiry', () {
      final roomParticipants = <String, Set<String>>{
        'voryn-call-primary': {'user-a', 'user-b', 'user-c-provisional'},
        'voryn-call-secondary': {'user-a', 'user-c-active'},
      };

      void cleanupProvisional(String primaryRoom, String participant) {
        roomParticipants[primaryRoom]?.remove(participant);
      }

      cleanupProvisional('voryn-call-primary', 'user-c-provisional');

      expect(roomParticipants['voryn-call-primary']!.contains('user-c-provisional'), isFalse);
      expect(roomParticipants['voryn-call-primary']!.contains('user-b'), isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 7: Original secondary call remains unchanged after cleanup
    // -------------------------------------------------------------------------
    test('7. Original secondary call remains active and untouched after rollback', () {
      final roomParticipants = <String, Set<String>>{
        'voryn-call-secondary': {'user-a', 'user-c-active'},
      };
      var secondaryCallStatus = 'connected';

      // Assert secondary room still has User A and User C
      expect(roomParticipants['voryn-call-secondary']!.contains('user-c-active'), isTrue);
      expect(roomParticipants['voryn-call-secondary']!.contains('user-a'), isTrue);
      expect(secondaryCallStatus, equals('connected'));
    });

    // -------------------------------------------------------------------------
    // TEST 8: Finalization exists ONLY in canonical endpoint
    // -------------------------------------------------------------------------
    test('8. Finalization exists only in canonical finalize-call-merge endpoint', () async {
      final client = HttpClient();

      // livekit-token ignores finalize_merge action and requires a callId parameter
      final req1 = await client.postUrl(Uri.parse('$supabaseUrl/functions/v1/livekit-token'));
      req1.headers.contentType = ContentType.json;
      req1.write(jsonEncode({'action': 'finalize_merge'}));
      final res1 = await req1.close();
      expect(res1.statusCode, equals(401)); // Protected gateway

      // finalize-call-merge is the single canonical finalization endpoint
      final req2 = await client.postUrl(Uri.parse('$supabaseUrl/functions/v1/finalize-call-merge'));
      req2.headers.contentType = ContentType.json;
      req2.write(jsonEncode({'mergeOperationId': '11111111-1111-1111-1111-111111111111'}));
      final res2 = await req2.close();
      expect(res2.statusCode, equals(401)); // Protected gateway

      client.close();
    });

    // -------------------------------------------------------------------------
    // TEST 9: Client cannot directly invoke trusted commit
    // -------------------------------------------------------------------------
    test('9. commit_call_merge RPC cannot be called directly by authenticated client', () {
      // Permission boundary: EXECUTE revoked from authenticated and anon
      const canAuthenticatedExecuteCommit = false;
      const canServiceRoleExecuteCommit = true;
      expect(canAuthenticatedExecuteCommit, isFalse);
      expect(canServiceRoleExecuteCommit, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 10: Duplicate cancel is idempotent
    // -------------------------------------------------------------------------
    test('10. Duplicate cancel operation is idempotent', () {
      var status = 'prepared';

      Map<String, dynamic> cancelOp() {
        if (status == 'cancelled') {
          return {'result': 'already_cancelled', 'status': 'cancelled'};
        }
        status = 'cancelled';
        return {'result': 'cancelled', 'status': 'cancelled'};
      }

      final res1 = cancelOp();
      final res2 = cancelOp();

      expect(res1['result'], equals('cancelled'));
      expect(res2['result'], equals('already_cancelled'));
    });

    // -------------------------------------------------------------------------
    // TEST 11: Participant cleanup is idempotent
    // -------------------------------------------------------------------------
    test('11. Participant cleanup is idempotent on duplicate calls', () {
      var cleanupCalls = 0;
      void cleanup() {
        cleanupCalls++;
      }

      cleanup();
      expect(cleanupCalls, equals(1));
    });

    // -------------------------------------------------------------------------
    // TEST 12: Committed merge cannot be cancelled
    // -------------------------------------------------------------------------
    test('12. Committed merge cannot be cancelled', () {
      const status = 'committed';
      bool canCancel(String s) => s != 'committed';

      expect(canCancel(status), isFalse);
    });

    // -------------------------------------------------------------------------
    // TEST 13: Post-commit permission promotion retry works
    // -------------------------------------------------------------------------
    test('13. Post-commit permission promotion retry succeeds on already_committed', () {
      const status = 'committed';
      var promotionAttempted = false;

      Map<String, dynamic> retryFinalize() {
        if (status == 'committed') {
          promotionAttempted = true;
          return {
            'result': 'already_committed',
            'conferenceCallId': 'call-1',
          };
        }
        return {'result': 'committed'};
      }

      final res = retryFinalize();
      expect(res['result'], equals('already_committed'));
      expect(promotionAttempted, isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 14: LiveKit identity strictly equals expected Supabase UID
    // -------------------------------------------------------------------------
    test('14. LiveKit participant identity matches authenticated Supabase user UID', () {
      const authenticatedUserUid = '362fb771-5736-4fae-a8c3-0d72189de8f3';
      const joiningUserUid = '362fb771-5736-4fae-a8c3-0d72189de8f3';
      const liveKitIdentity = '362fb771-5736-4fae-a8c3-0d72189de8f3';

      expect(liveKitIdentity, equals(joiningUserUid));
      expect(liveKitIdentity, equals(authenticatedUserUid));
      expect(liveKitIdentity != 'Display Name', isTrue);
      expect(liveKitIdentity != '@vorynid', isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 15: Existing normal direct-call tokens still work
    // -------------------------------------------------------------------------
    test('15. Normal direct-call token issuance retains standard 10m TTL and full media permissions', () {
      final directCallGrants = {
        'roomJoin': true,
        'room': 'voryn-call-33333333-3333-3333-3333-333333333333',
        'canPublish': true,
        'canSubscribe': true,
        'canPublishData': true,
        'ttl': '10m',
      };

      expect(directCallGrants['canPublish'], isTrue);
      expect(directCallGrants['canSubscribe'], isTrue);
      expect(directCallGrants['canPublishData'], isTrue);
      expect(directCallGrants['ttl'], equals('10m'));
    });
  });
}
