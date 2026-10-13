import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/meetings/meetings_screen.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';

class MockVorynMeetingServiceForCreation extends VorynMeetingService {
  MockVorynMeetingServiceForCreation({
    this.createDelay = Duration.zero,
    this.shouldThrow = false,
    this.throwException,
    this.meetingToReturn,
  });

  final Duration createDelay;
  final bool shouldThrow;
  final Object? throwException;
  final VorynCreatedMeeting? meetingToReturn;

  int createCallCount = 0;
  String? lastTitle;
  String? lastAccess;

  @override
  Future<VorynCreatedMeeting> createMeeting({
    required String title,
    String access = 'link',
  }) async {
    final clean = title.trim();
    if (clean.isEmpty || clean.length > 60) {
      throw ArgumentError('Meeting title must be between 1 and 60 characters');
    }

    createCallCount++;
    lastTitle = title;
    lastAccess = access;

    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }

    if (shouldThrow) {
      throw throwException ?? Exception('PGRST202: Could not find function');
    }

    return meetingToReturn ??
        VorynCreatedMeeting(
          id: 'test-uuid-1111-2222',
          title: title,
          joinCode: 'k7q-mzx-p2f',
          access: access,
          status: 'ready',
          livekitRoomName: 'voryn-meeting-test-uuid-1111-2222',
        );
  }
}

void main() {
  group('Part A — Meeting Creation Verification Tests', () {
    test('VorynCreatedMeeting.fromJson handles server responses with and without livekit_room_name', () {
      final jsonWithRoom = {
        'id': 'abc-123',
        'title': 'Standup',
        'join_code': '123-456-789',
        'access': 'link',
        'status': 'ready',
        'livekit_room_name': 'custom-room-abc',
      };
      final m1 = VorynCreatedMeeting.fromJson(jsonWithRoom);
      expect(m1.id, 'abc-123');
      expect(m1.title, 'Standup');
      expect(m1.joinCode, '123-456-789');
      expect(m1.livekitRoomName, 'custom-room-abc');

      final jsonWithoutRoom = {
        'id': 'def-456',
        'title': 'Planning',
        'join_code': '987-654-321',
        'access': 'invited',
        'status': 'ready',
      };
      final m2 = VorynCreatedMeeting.fromJson(jsonWithoutRoom);
      expect(m2.id, 'def-456');
      expect(m2.title, 'Planning');
      expect(m2.livekitRoomName, 'voryn-meeting-def-456');
    });

    test('Meeting title validation rejects empty and over-length titles', () async {
      final mock = MockVorynMeetingServiceForCreation();
      VorynMeetingService.instance = mock;

      expect(
        () => mock.createMeeting(title: ''),
        throwsA(isA<ArgumentError>()),
      );

      final tooLong = 'A' * 61;
      expect(
        () => mock.createMeeting(title: tooLong),
        throwsA(isA<ArgumentError>()),
      );
    });

    testWidgets('NewMeetingScreen creates meeting and navigates on success', (tester) async {
      final mock = MockVorynMeetingServiceForCreation();
      VorynMeetingService.instance = mock;

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const NewMeetingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create a Voryn meeting'), findsOneWidget);
      expect(find.text('Create meeting'), findsOneWidget);

      await tester.tap(find.text('Create meeting'));
      await tester.pumpAndSettle();

      expect(mock.createCallCount, 1);
      expect(mock.lastTitle, 'Team Meeting');
      expect(mock.lastAccess, 'link');

      // Navigated to MeetingCreatedScreen
      expect(find.text('Meeting ready'), findsOneWidget);
      expect(find.text('k7q-mzx-p2f'), findsOneWidget);
    });

    testWidgets('NewMeetingScreen stays on form and displays user-friendly error on failure', (tester) async {
      final mock = MockVorynMeetingServiceForCreation(
        shouldThrow: true,
        throwException: Exception('Could not find the function in schema cache'),
      );
      VorynMeetingService.instance = mock;

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const NewMeetingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create meeting'));
      await tester.pumpAndSettle();

      expect(mock.createCallCount, 1);
      // Remained on form
      expect(find.text('Create a Voryn meeting'), findsOneWidget);
      expect(find.textContaining('Could not find the function in schema cache'), findsOneWidget);
    });

    testWidgets('NewMeetingScreen prevents duplicate submissions during inflight request', (tester) async {
      final mock = MockVorynMeetingServiceForCreation(
        createDelay: const Duration(milliseconds: 500),
      );
      VorynMeetingService.instance = mock;

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: const NewMeetingScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap once
      await tester.tap(find.text('Create meeting'));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap again while request is inflight
      await tester.tap(find.text('Creating...'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Only one call should have been made
      expect(mock.createCallCount, 1);
    });
  });
}
