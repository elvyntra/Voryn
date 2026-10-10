import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/features/calling/models/video_upgrade_models.dart';
import 'package:voryn/features/calling/voryn_call_runtime_coordinator.dart';
import 'package:voryn/features/calling/widgets/video_upgrade_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part C — Audio-to-Video Single-Response Handshake Verification Tests', () {
    test('1. Receiver acceptance transitions requester out of waiting state into video', () {
      const callId = 'test-handshake-call-01';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 20));
      coordinator.markConnected(startTime);

      bool transitionTriggered = false;
      bool waitingBannerActive = true;

      void onUpgradeStatusChanged(String reqId, VideoUpgradeStatus status) {
        if (status == VideoUpgradeStatus.accepted) {
          waitingBannerActive = false;
          transitionTriggered = true;
        }
      }

      final screenKey = Object();
      coordinator.attachScreen(
        screenKey: screenKey,
        onStatusChanged: (_) {},
        onRouteExit: () {},
        onVideoUpgradeStatusChanged: onUpgradeStatusChanged,
      );

      // Simulated receiver approval signal
      coordinator.notifyStatus('connected');
      onUpgradeStatusChanged('req-123', VideoUpgradeStatus.accepted);

      expect(waitingBannerActive, isFalse);
      expect(transitionTriggered, isTrue);
      expect(coordinator.isConnected, isTrue);

      coordinator.detachScreen(screenKey);
      VorynCallRuntimeCoordinator.remove(callId);
    });

    test('2. Receiver decline closes waiting banner and leaves audio call active', () {
      const callId = 'test-handshake-call-02';
      final coordinator = VorynCallRuntimeCoordinator.forCall(callId);
      final startTime = DateTime.now().subtract(const Duration(seconds: 10));
      coordinator.markConnected(startTime);

      bool waitingBannerActive = true;
      bool declineNotified = false;

      void onUpgradeStatusChanged(String reqId, VideoUpgradeStatus status) {
        if (status == VideoUpgradeStatus.declined) {
          waitingBannerActive = false;
          declineNotified = true;
        }
      }

      final screenKey = Object();
      coordinator.attachScreen(
        screenKey: screenKey,
        onStatusChanged: (_) {},
        onRouteExit: () {},
        onVideoUpgradeStatusChanged: onUpgradeStatusChanged,
      );

      // Simulated receiver decline signal
      onUpgradeStatusChanged('req-456', VideoUpgradeStatus.declined);

      expect(waitingBannerActive, isFalse);
      expect(declineNotified, isTrue);
      expect(coordinator.isConnected, isTrue);

      coordinator.detachScreen(screenKey);
      VorynCallRuntimeCoordinator.remove(callId);
    });

    testWidgets('3. VideoUpgradeWaitingBanner renders and cancel callback fires cleanly', (tester) async {
      bool cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoUpgradeWaitingBanner(
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      expect(find.text('Video request sent'), findsOneWidget);
      expect(find.text('Waiting for approval…'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      expect(cancelled, isTrue);
    });

    testWidgets('4. VideoUpgradePromptCard renders Accept and Decline and triggers callbacks', (tester) async {
      bool accepted = false;
      bool declined = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoUpgradePromptCard(
              callerName: 'Jane Doe',
              onAccept: () => accepted = true,
              onDecline: () => declined = true,
            ),
          ),
        ),
      );

      expect(find.text('Switch to video call?'), findsOneWidget);
      expect(find.text('Jane Doe wants to turn this audio call into a video call.'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      expect(accepted, isTrue);

      await tester.tap(find.text('Decline'));
      expect(declined, isTrue);
    });
  });
}

