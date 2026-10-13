import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/voryn_call_history_service.dart';
import 'package:voryn/features/recents/recents_screen.dart';

class FakeVorynCallHistoryService extends VorynCallHistoryService {
  FakeVorynCallHistoryService({
    this.itemsToReturn = const [],
    this.shouldThrow = false,
    this.exceptionToThrow,
  });

  List<VorynCallHistoryItem> itemsToReturn;
  bool shouldThrow;
  Object? exceptionToThrow;
  int loadCount = 0;

  @override
  Future<List<VorynCallHistoryItem>> load() async {
    loadCount++;
    if (shouldThrow) {
      throw exceptionToThrow ?? Exception('Failed to fetch recent calls');
    }
    return itemsToReturn;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: VorynTheme.light,
    darkTheme: VorynTheme.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  group('Part B — Recents Call History Verification Tests', () {
    test('VorynCallHistoryItem parsing and helper getters', () {
      final now = DateTime.now();
      final itemMap = {
        'id': 'call-1',
        'other_uid': 'user-2',
        'display_name': 'Alice Smith',
        'voryn_id': 'alicesmith',
        'call_type': 'video',
        'direction': 'incoming',
        'status': 'missed',
        'created_at': now.toIso8601String(),
        'ended_at': null,
      };

      final item = VorynCallHistoryItem.fromMap(itemMap);
      expect(item.id, 'call-1');
      expect(item.otherUid, 'user-2');
      expect(item.displayName, 'Alice Smith');
      expect(item.vorynId, 'alicesmith');
      expect(item.callType, 'video');
      expect(item.direction, 'incoming');
      expect(item.status, 'missed');
      expect(item.isMissed, isTrue);
      expect(item.group, 'Today');
      expect(item.initials, 'AS');
      expect(item.durationFormatted, isNull);

      final mockUser = item.toMockUser();
      expect(mockUser.name, 'Alice Smith');
      expect(mockUser.id, '@alicesmith');
      expect(mockUser.backendUid, 'user-2');
    });

    test('VorynCallHistoryItem completed duration and status helpers', () {
      final now = DateTime.now();
      final start = now.subtract(const Duration(minutes: 5, seconds: 42));
      final itemMap = {
        'id': 'call-2',
        'other_uid': 'user-3',
        'display_name': 'Bob Vance',
        'voryn_id': 'bobvance',
        'call_type': 'audio',
        'direction': 'outgoing',
        'status': 'completed',
        'created_at': start.toIso8601String(),
        'ended_at': now.toIso8601String(),
      };

      final item = VorynCallHistoryItem.fromMap(itemMap);
      expect(item.isMissed, isFalse);
      expect(item.durationFormatted, '5m 42s');
      expect(item.initials, 'BV');
    });

    testWidgets('RecentsScreen displays empty state when live history is empty',
        (tester) async {
      final fakeService = FakeVorynCallHistoryService(itemsToReturn: []);

      await tester.pumpWidget(_wrap(RecentsScreen(historyService: fakeService)));
      await tester.pumpAndSettle();

      expect(find.text('Recents'), findsOneWidget);
      expect(find.text('No recent calls'), findsOneWidget);
      expect(find.text('Your Voryn calls will appear here.'), findsOneWidget);
      expect(fakeService.loadCount, 1);
    });

    testWidgets('RecentsScreen renders fetched live call items and groupings',
        (tester) async {
      final now = DateTime.now();
      final items = [
        VorynCallHistoryItem(
          id: 'c-1',
          otherUid: 'u-1',
          displayName: 'Elena Rostova',
          vorynId: 'elena_r',
          callType: 'audio',
          direction: 'outgoing',
          status: 'completed',
          createdAt: now,
          endedAt: now.add(const Duration(minutes: 2, seconds: 15)),
        ),
        VorynCallHistoryItem(
          id: 'c-2',
          otherUid: 'u-2',
          displayName: 'David Miller',
          vorynId: 'david_m',
          callType: 'video',
          direction: 'incoming',
          status: 'missed',
          createdAt: now,
        ),
      ];

      final fakeService = FakeVorynCallHistoryService(itemsToReturn: items);

      await tester.pumpWidget(_wrap(RecentsScreen(historyService: fakeService)));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.text('David Miller'), findsOneWidget);
      expect(find.text('2m 15s'), findsOneWidget);
      expect(find.textContaining('Missed video call'), findsOneWidget);
      expect(find.textContaining('Outgoing audio'), findsOneWidget);
    });

    testWidgets('RecentsScreen filters by search text', (tester) async {
      final now = DateTime.now();
      final items = [
        VorynCallHistoryItem(
          id: 'c-1',
          otherUid: 'u-1',
          displayName: 'Elena Rostova',
          vorynId: 'elena_r',
          callType: 'audio',
          direction: 'outgoing',
          status: 'completed',
          createdAt: now,
        ),
        VorynCallHistoryItem(
          id: 'c-2',
          otherUid: 'u-2',
          displayName: 'David Miller',
          vorynId: 'david_m',
          callType: 'video',
          direction: 'incoming',
          status: 'missed',
          createdAt: now,
        ),
      ];

      final fakeService = FakeVorynCallHistoryService(itemsToReturn: items);

      await tester.pumpWidget(_wrap(RecentsScreen(historyService: fakeService)));
      await tester.pumpAndSettle();

      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.text('David Miller'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Elena');
      await tester.pumpAndSettle();

      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.text('David Miller'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pumpAndSettle();

      expect(find.text('No recent calls'), findsOneWidget);
    });

    testWidgets('RecentsScreen displays error state with Retry button on failure',
        (tester) async {
      final fakeService = FakeVorynCallHistoryService(
        shouldThrow: true,
        exceptionToThrow: Exception('Server error 500'),
      );

      await tester.pumpWidget(_wrap(RecentsScreen(historyService: fakeService)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load call history'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(fakeService.loadCount, 1);

      // Now configure service to succeed and tap Retry
      fakeService.shouldThrow = false;
      fakeService.itemsToReturn = [
        VorynCallHistoryItem(
          id: 'c-1',
          otherUid: 'u-1',
          displayName: 'Elena Rostova',
          vorynId: 'elena_r',
          callType: 'audio',
          direction: 'outgoing',
          status: 'completed',
          createdAt: DateTime.now(),
        ),
      ];

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(fakeService.loadCount, 2);
      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.textContaining('Failed to load call history'), findsNothing);
    });
  });
}

