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
}
