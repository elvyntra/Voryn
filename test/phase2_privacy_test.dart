import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/presence/voryn_presence_service.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/connect/mock_voryn_state.dart';
import 'package:voryn/features/connect/user_interaction_screens.dart';
import 'package:voryn/features/contacts/voryn_contact_service.dart';
import 'package:voryn/features/profile/voryn_profile_service.dart';
import 'package:voryn/shared/widgets/voryn_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2: Privacy Settings Model & Parsing', () {
    test('VorynPrivacySettings defaults when map is empty', () {
      final settings = VorynPrivacySettings.fromMap({});
      expect(settings.dndEnabled, isFalse);
      expect(settings.whoCanCall, 'everyone');
      expect(settings.showOnlineStatus, isTrue);
    });

    test('VorynPrivacySettings correctly parses database row', () {
      final settings = VorynPrivacySettings.fromMap({
        'dnd_enabled': true,
        'who_can_call': 'saved_contacts',
        'show_online_status': false,
      });
      expect(settings.dndEnabled, isTrue);
      expect(settings.whoCanCall, 'saved_contacts');
      expect(settings.showOnlineStatus, isFalse);
    });

    test('VorynPrivacySettings copyWith works correctly', () {
      const initial = VorynPrivacySettings(
        dndEnabled: false,
        whoCanCall: 'everyone',
        showOnlineStatus: true,
      );
      final updated = initial.copyWith(dndEnabled: true, whoCanCall: 'nobody');
      expect(updated.dndEnabled, isTrue);
      expect(updated.whoCanCall, 'nobody');
      expect(updated.showOnlineStatus, isTrue);
    });
  });

  group('Phase 2: Blocked User Model', () {
    test('VorynBlockedUser parses full_name as display_name and timestamp', () {
      final blocked = VorynBlockedUser.fromMap({
        'uid': 'user-123',
        'display_name': 'Sarah Connor',
        'voryn_id': 'sarah_c',
        'avatar_url': 'https://example.com/avatar.jpg',
        'blocked_at': '2026-09-18T12:00:00Z',
      });
      expect(blocked.uid, 'user-123');
      expect(blocked.displayName, 'Sarah Connor');
      expect(blocked.vorynId, 'sarah_c');
      expect(blocked.avatarUrl, 'https://example.com/avatar.jpg');
      expect(blocked.blockedAt.isUtc, isTrue);
    });
  });

  group('Phase 2: VorynPresenceService Lifecycle & Active Call Invariants', () {
    test('Call connection sets isInCall true and call end resets isInCall', () {
      expect(VorynPresenceService.isInCall, isFalse);
      VorynPresenceService.onCallConnected();
      expect(VorynPresenceService.isInCall, isTrue);
      VorynPresenceService.onCallEnded();
      expect(VorynPresenceService.isInCall, isFalse);
    });

    test(
      'AppLifecycleState.inactive is ignored and does not reset isInCall',
      () {
        VorynPresenceService.onCallConnected();
        expect(VorynPresenceService.isInCall, isTrue);
        VorynPresenceService.onLifecycleChanged(AppLifecycleState.inactive);
        expect(VorynPresenceService.isInCall, isTrue);
        VorynPresenceService.onCallEnded();
      },
    );
  });

  group('Phase 2: User Preview Direct Actions UI', () {
    testWidgets(
      'UserPreviewScreen renders 3 equal-width action tiles and no generic Connect button',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.resetPhysicalSize);

        final testUser = VorynMockUser(
          customName: null,
          id: '@alex_test',
          name: 'Alex Mercer',
          phone: '+1 555 0199',
          email: 'alex@example.com',
          presence: VorynPresenceStatus.online,
          initials: 'AM',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: VorynTheme.dark,
            home: UserPreviewScreen(user: testUser),
          ),
        );
        await tester.pump();

        // Verify the 3 action tiles
        expect(find.text('Audio call'), findsOneWidget);
        expect(find.text('Video call'), findsOneWidget);
        expect(find.text('Message'), findsOneWidget);

        // Verify generic 'Connect' button is completely removed
        expect(find.text('Connect'), findsNothing);

        // Verify direct actions contain proper icons
        expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
        expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
        expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      },
    );
  });
}
