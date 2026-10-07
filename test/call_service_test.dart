import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/features/calling/voryn_call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VorynCallService active call persistence & reconciliation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('markActiveCall stores active call ID in SharedPreferences', () async {
      const service = VorynCallService();
      await service.markActiveCall('test-call-123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('voryn.active_call_id'), 'test-call-123');
    });

    test('clearActiveCall removes matching active call ID', () async {
      const service = VorynCallService();
      await service.markActiveCall('test-call-123');
      await service.clearActiveCall('test-call-123');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('voryn.active_call_id'), isNull);
    });

    test('clearActiveCall ignores non-matching call ID', () async {
      const service = VorynCallService();
      await service.markActiveCall('test-call-123');
      await service.clearActiveCall('other-call-456');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('voryn.active_call_id'), 'test-call-123');
    });

    test(
      'reconcileStaleActiveCallOnStartup cleans up when no backend client is active',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('voryn.active_call_id', 'stale-call-789');

        const service = VorynCallService();
        await service.reconcileStaleActiveCallOnStartup();

        expect(prefs.getString('voryn.active_call_id'), isNull);
      },
    );
  });


  group('VorynCallService critical signaling & FCM dispatch retry', () {
    const service = VorynCallService();

    test('FCM dispatch succeeds on first attempt', () async {
      var callCount = 0;
      final result = await service.dispatchCallNotificationWithRetry(
        callId: 'call-ok-1',
        isAuthenticatedOverride: () => true,
        retryDelayOverride: Duration.zero,
        invokeOverride: (name, {body}) async {
          callCount++;
          return const FunctionResponse(data: {'delivered': 1}, status: 200);
        },
      );

      expect(result, isTrue);
      expect(callCount, 1);
    });

    test('Permanent HTTP 401/403 errors are not retried', () async {
      var callCount401 = 0;
      final result401 = await service.dispatchCallNotificationWithRetry(
        callId: 'call-auth-err',
        isAuthenticatedOverride: () => true,
        retryDelayOverride: Duration.zero,
        invokeOverride: (name, {body}) async {
          callCount401++;
          throw const FunctionsHttpException(status: 401, details: 'Authentication required');
        },
      );

      expect(result401, isFalse);
      expect(callCount401, 1); // No retry!

      var callCount403 = 0;
      final result403 = await service.dispatchCallNotificationWithRetry(
        callId: 'call-forbidden-err',
        isAuthenticatedOverride: () => true,
        retryDelayOverride: Duration.zero,
        invokeOverride: (name, {body}) async {
          callCount403++;
          throw const FunctionsHttpException(status: 403, details: 'Call unavailable');
        },
      );

      expect(result403, isFalse);
      expect(callCount403, 1); // No retry!
    });

    test('Transient 500 error is retried durably and succeeds on subsequent attempt', () async {
      var callCount = 0;
      final result = await service.dispatchCallNotificationWithRetry(
        callId: 'call-transient-500',
        isAuthenticatedOverride: () => true,
        retryDelayOverride: Duration.zero,
        getCallOverride: (callId) async => {'status': 'calling'},
        invokeOverride: (name, {body}) async {
          callCount++;
          if (callCount == 1) {
            throw const FunctionsHttpException(status: 500, details: 'Edge function cold start error');
          }
          return const FunctionResponse(data: {'delivered': 1}, status: 200);
        },
      );

      expect(result, isTrue);
      expect(callCount, 2);
    });

    test('Transient network fetch exception is retried up to maxAttempts', () async {
      var callCount = 0;
      final result = await service.dispatchCallNotificationWithRetry(
        callId: 'call-transient-net',
        isAuthenticatedOverride: () => true,
        maxAttempts: 3,
        retryDelayOverride: Duration.zero,
        getCallOverride: (callId) async => {'status': 'calling'},
        invokeOverride: (name, {body}) async {
          callCount++;
          throw const FunctionsFetchException(details: 'Connection reset');
        },
      );

      expect(result, isFalse);
      expect(callCount, 3);
    });

    test('Backend call state is authoritative: aborts retry if call is no longer calling', () async {
      var callCount = 0;
      var callStatus = 'calling';

      final result = await service.dispatchCallNotificationWithRetry(
        callId: 'call-cancelled-backend',
        isAuthenticatedOverride: () => true,
        maxAttempts: 3,
        retryDelayOverride: Duration.zero,
        getCallOverride: (callId) async => {'status': callStatus},
        invokeOverride: (name, {body}) async {
          callCount++;
          // First attempt fails transients
          callStatus = 'cancelled'; // Remote party or backend cancelled call
          throw const FunctionsHttpException(status: 500, details: 'Server error');
        },
      );

      expect(result, isFalse);
      expect(callCount, 1); // Attempt 2 aborted before invoke because status changed to cancelled!
    });
  });
}
