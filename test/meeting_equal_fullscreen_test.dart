import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/group_call_screen.dart';
import 'package:voryn/features/calling/voryn_livekit_service.dart';
import 'package:voryn/features/meetings/meeting_room_screen.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';
import 'package:voryn/features/meetings/services/voryn_meeting_service.dart';

class FakeVideoTrack extends Fake implements livekit.VideoTrack {
  @override
  final String? sid;

  FakeVideoTrack({this.sid});
}

class FakeTestRoom extends Fake implements livekit.Room {
  final List<VoidCallback> _listeners = [];
  final livekit.ConnectionState _state = livekit.ConnectionState.connected;

  @override
  livekit.ConnectionState get connectionState => _state;

  @override
  UnmodifiableMapView<String, livekit.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView({});

  @override
  UnmodifiableListView<livekit.Participant> get activeSpeakers =>
      UnmodifiableListView([]);

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

class FakeTestSession implements VorynLiveKitSession {
  bool micEnabled;
  bool cameraEnabled;
  bool speakerEnabled;
  bool screenShareEnabled;
  bool held;
  bool disconnected;
  final FakeTestRoom _room;

  FakeTestSession({
    this.micEnabled = true,
    this.cameraEnabled = true,
    this.speakerEnabled = true,
    this.screenShareEnabled = false,
    this.held = false,
    this.disconnected = false,
    FakeTestRoom? room,
  }) : _room = room ?? FakeTestRoom();

  @override
  bool get isConnected => !disconnected;

  @override
  bool get isHeld => held;

  @override
  livekit.VideoTrack? get localVideoTrack =>
      cameraEnabled ? FakeVideoTrack(sid: 'trk_local') : null;

  @override
  livekit.VideoTrack? get remoteVideoTrack => null;

  @override
  bool get isScreenShareEnabled => screenShareEnabled;

  @override
  livekit.VideoTrack? get localScreenShareTrack => null;

  @override
  livekit.VideoTrack? get remoteScreenShareTrack => null;

  @override
  String? get screenSharePresenterName => null;

  @override
  bool get hasRemoteScreenShare => false;

  @override
  bool get hasActiveScreenShare => false;

  @override
  livekit.Room get room => _room;

  @override
  Future<void> hold() async => held = true;

  @override
  Future<void> resume({bool restoreMic = true, bool restoreCamera = false}) async {
    held = false;
    micEnabled = restoreMic;
    cameraEnabled = restoreCamera;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async => micEnabled = enabled;

  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    cameraEnabled = enabled;
    return true;
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async => speakerEnabled = enabled;

  @override
  Future<bool> setScreenShareEnabled(bool enabled) async {
    screenShareEnabled = enabled;
    return true;
  }

  @override
  Future<void> disconnect() async => disconnected = true;
}

class FakeMeetingService extends Fake implements VorynMeetingService {
  @override
  Future<MeetingEndResult> endMeetingForEveryone(String meetingId) async {
    return const MeetingEndResult(
      status: MeetingEndStatus.ended,
      dbEnded: true,
      roomDeleted: true,
    );
  }

  @override
  Future<void> leaveMeeting(String meetingId) async {}
}

List<GroupCallParticipant> createTestParticipants(int count, {bool withVideo = true}) {
  return List.generate(count, (i) {
    final id = i == 0 ? 'user_me' : 'user_$i';
    final name = i == 0 ? 'You' : 'User $i';
    final initials = i == 0 ? 'YO' : 'U$i';
    return GroupCallParticipant(
      id: id,
      name: name,
      initials: initials,
      isYou: i == 0,
      isMuted: false,
      isCameraOff: !withVideo,
      videoTrack: withVideo ? FakeVideoTrack(sid: 'trk_$id') : null,
    );
  });
}

VorynJoinedMeeting createJoinedMeeting({bool isHost = true}) {
  return VorynJoinedMeeting(
    meetingId: 'meet-test-123',
    title: 'Design Review',
    livekitRoomName: 'room-test',
    role: isHost ? 'host' : 'participant',
    status: 'active',
    access: 'link',
    livekitToken: 'token-test',
    livekitUrl: 'wss://test.livekit.cloud',
    initialMic: true,
    initialCamera: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.voryn.app/lock_screen'),
      (call) async => null,
    );
  });

  void setupViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('Meeting & Group Call: Dynamic Equal Grid and Fullscreen Switching', () {
    testWidgets('1. MeetingRoomScreen: 3 participants render in Dynamic Equal Grid', (tester) async {
      setupViewport(tester);
      final participants = createTestParticipants(3, withVideo: true);
      final session = FakeTestSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingRoomScreen(
            joinedMeeting: createJoinedMeeting(),
            existingSession: session,
            customParticipants: participants,
            meetingService: FakeMeetingService(),
          ),
        ),
      );
      await tester.pump();

      // All 3 participants are visible
      expect(find.text('You'), findsWidgets);
      expect(find.text('User 1'), findsWidgets);
      expect(find.text('User 2'), findsWidgets);

      // Verify fullscreen toggle buttons exist for each tile when >= 3
      expect(find.byKey(const ValueKey('fullscreen_btn_user_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_2')), findsOneWidget);

      // Verify equal screen button is not showing while in equal grid
      expect(find.byKey(const Key('equal_screen_btn')), findsNothing);
    });

    testWidgets('2. MeetingRoomScreen: Switch to fullscreen on participant and PiP deck renders', (tester) async {
      setupViewport(tester);
      final participants = createTestParticipants(3, withVideo: true);
      final session = FakeTestSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingRoomScreen(
            joinedMeeting: createJoinedMeeting(),
            existingSession: session,
            customParticipants: participants,
            meetingService: FakeMeetingService(),
          ),
        ),
      );
      await tester.pump();

      // Tap fullscreen on User 1
      await tester.tap(find.byKey(const ValueKey('fullscreen_btn_user_1')));
      await tester.pumpAndSettle();

      // "All Screens Equal" button is now visible
      expect(find.byKey(const Key('equal_screen_btn')), findsOneWidget);

      // PiP deck of other participants is visible
      expect(find.byKey(const Key('meeting_pip_deck')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_2')), findsOneWidget);

      // Now tap User 2 in PiP deck to switch fullscreen to User 2
      await tester.tap(find.byKey(const ValueKey('pip_switch_user_2')));
      await tester.pumpAndSettle();

      // User 2 is now dominant; PiP deck shows user_me and user_1
      expect(find.byKey(const Key('equal_screen_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_1')), findsOneWidget);

      // Tap "All Screens Equal" button to restore equal grid
      await tester.tap(find.byKey(const Key('equal_screen_btn')));
      await tester.pumpAndSettle();

      // Equal grid restored: equal_screen_btn is gone and all 3 tiles have fullscreen_btns
      expect(find.byKey(const Key('equal_screen_btn')), findsNothing);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_2')), findsOneWidget);
    });

    testWidgets('3. GroupCallScreen: 3+ participants dynamic equal grid & fullscreen switching', (tester) async {
      setupViewport(tester);
      final participants = createTestParticipants(4, withVideo: true);
      final session = FakeTestSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: GroupCallScreen(
            callId: 'call-grp-1',
            title: 'Project Standup',
            participants: participants,
            existingSession: session,
          ),
        ),
      );
      await tester.pump();

      // 4 participants rendered with fullscreen buttons
      expect(find.byKey(const ValueKey('fullscreen_btn_user_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_3')), findsOneWidget);

      // Switch to User 2 fullscreen
      await tester.tap(find.byKey(const ValueKey('fullscreen_btn_user_2')));
      await tester.pumpAndSettle();

      // Group PiP deck is visible with 3 other participants
      expect(find.byKey(const Key('group_pip_deck')), findsOneWidget);
      expect(find.byKey(const Key('equal_screen_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip_switch_user_3')), findsOneWidget);

      // Tap User 3 in PiP deck to switch dominant screen
      await tester.tap(find.byKey(const ValueKey('pip_switch_user_3')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pip_switch_user_2')), findsOneWidget);

      // Tap "All Screens Equal" to return to equal grid
      await tester.tap(find.byKey(const Key('equal_screen_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('equal_screen_btn')), findsNothing);
      expect(find.byKey(const ValueKey('fullscreen_btn_user_3')), findsOneWidget);
    });

    testWidgets('4. Equal Grid dynamically divides stage equally without black voids', (tester) async {
      setupViewport(tester);
      final participants = createTestParticipants(3, withVideo: false);
      final session = FakeTestSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: VorynTheme.dark,
          home: MeetingRoomScreen(
            joinedMeeting: createJoinedMeeting(),
            existingSession: session,
            customParticipants: participants,
            meetingService: FakeMeetingService(),
          ),
        ),
      );
      await tester.pump();

      // For 3 participants in portrait: 3 equal height rows
      final tile1 = tester.getRect(find.byKey(const ValueKey('audio_tile_user_me')));
      final tile2 = tester.getRect(find.byKey(const ValueKey('audio_tile_user_1')));
      final tile3 = tester.getRect(find.byKey(const ValueKey('audio_tile_user_2')));

      // Heights should be equal (within 1.0 px due to integer rounding)
      expect((tile1.height - tile2.height).abs(), lessThanOrEqualTo(1.0));
      expect((tile2.height - tile3.height).abs(), lessThanOrEqualTo(1.0));

      // Widths should span full available width
      expect(tile1.width, equals(tile2.width));
      expect(tile2.width, equals(tile3.width));
    });
  });
}
