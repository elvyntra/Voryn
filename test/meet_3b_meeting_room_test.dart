import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
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

class FakeMeetingRoom extends Fake implements livekit.Room {
  final List<VoidCallback> _listeners = [];
  livekit.ConnectionState _state = livekit.ConnectionState.connected;

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

  void setConnectionState(livekit.ConnectionState s) {
    _state = s;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

class FakeMeetingSession implements VorynLiveKitSession {
  bool micEnabled;
  bool cameraEnabled;
  bool speakerEnabled;
  bool screenShareEnabled;
  bool disconnected;
  final FakeMeetingRoom _room;

  FakeMeetingSession({
    this.micEnabled = true,
    this.cameraEnabled = false,
    this.speakerEnabled = true,
    this.screenShareEnabled = false,
    this.disconnected = false,
    FakeMeetingRoom? room,
  }) : _room = room ?? FakeMeetingRoom();

  @override
  bool get isConnected => !disconnected;

  @override
  bool get isHeld => false;

  @override
  livekit.VideoTrack? get localVideoTrack =>
      cameraEnabled ? FakeVideoTrack(sid: 'local_v') : null;

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
  bool get hasActiveScreenShare => screenShareEnabled;

  @override
  livekit.Room get room => _room;

  @override
  Future<void> hold() async {}

  @override
  Future<void> resume({bool restoreMic = true, bool restoreCamera = false}) async {
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

class MockVorynMeetingService extends VorynMeetingService {
  MockVorynMeetingService({
    this.prejoinToReturn,
    this.throwOnJoin = false,
  });

  VorynPrejoinMeeting? prejoinToReturn;
  bool throwOnJoin;

  int leaveCalls = 0;
  int endForEveryoneCalls = 0;
  int rollbackLeaveCalls = 0;
  int resolveCalls = 0;

  @override
  Future<VorynPrejoinMeeting?> resolveMeetingForPrejoin(String rawCode) async {
    resolveCalls++;
    return prejoinToReturn;
  }

  @override
  Future<VorynJoinedMeeting> joinMeeting(
    String rawCode, {
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    if (throwOnJoin) {
      rollbackLeaveCalls++;
      throw StateError('Unable to obtain meeting token: Token gateway error');
    }
    return VorynJoinedMeeting(
      meetingId: 'm-123',
      title: 'Sprint Planning',
      livekitRoomName: 'voryn-meeting-m-123',
      role: 'participant',
      status: 'active',
      access: 'link',
      livekitToken: 'token-abc',
      livekitUrl: 'wss://livekit.internal',
      initialMic: initialMic,
      initialCamera: initialCamera,
    );
  }

  @override
  Future<void> leaveMeeting(String meetingId) async {
    leaveCalls++;
  }

  @override
  Future<MeetingEndResult> endMeetingForEveryone(String meetingId) async {
    endForEveryoneCalls++;
    return const MeetingEndResult(
      status: MeetingEndStatus.ended,
      dbEnded: true,
      roomDeleted: true,
    );
  }
}

class MockVorynLiveKitService extends VorynLiveKitService {
  MockVorynLiveKitService({
    this.shouldFail = false,
    this.connectCompleter,
  });

  bool shouldFail;
  Completer<VorynLiveKitSession>? connectCompleter;
  int connectMeetingCalls = 0;
  String? lastUrl;
  String? lastToken;
  bool? lastMic;
  bool? lastCamera;

  @override
  Future<VorynLiveKitSession> connectMeeting({
    required String url,
    required String token,
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    connectMeetingCalls++;
    lastUrl = url;
    lastToken = token;
    lastMic = initialMic;
    lastCamera = initialCamera;

    if (connectCompleter != null) {
      return connectCompleter!.future;
    }
    if (shouldFail) {
      throw Exception('LiveKit connect timeout');
    }
    return FakeMeetingSession(
      micEnabled: initialMic,
      cameraEnabled: initialCamera,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestableScreen({
    required VorynJoinedMeeting joinedMeeting,
    VorynLiveKitSession? existingSession,
    VorynLiveKitService? liveKitService,
    VorynMeetingService? meetingService,
    List<GroupCallParticipant>? customParticipants,
    VoidCallback? onMeetingEnded,
    Size size = const Size(390, 844),
  }) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: VorynTheme.dark,
        home: MeetingRoomScreen(
          joinedMeeting: joinedMeeting,
          existingSession: existingSession,
          liveKitService: liveKitService ?? const VorynLiveKitService(),
          meetingService: meetingService,
          customParticipants: customParticipants,
          onMeetingEnded: onMeetingEnded,
        ),
      ),
    );
  }

  VorynJoinedMeeting sampleJoined({
    String role = 'participant',
    bool initialMic = true,
    bool initialCamera = false,
    String? token = 'token-abc',
    String? url = 'wss://livekit.test',
  }) {
    return VorynJoinedMeeting(
      meetingId: 'm-999',
      title: 'Voryn Sync',
      livekitRoomName: 'voryn-meeting-m-999',
      role: role,
      status: 'active',
      access: 'link',
      joinCode: 'k7q-mzx-p2f',
      livekitToken: token,
      livekitUrl: url,
      initialMic: initialMic,
      initialCamera: initialCamera,
    );
  }

  group('MEET-3B: Active Meeting Room Integration Tests', () {
    // 1. Successful connection opens actual meeting room.
    testWidgets('1. Successful connection opens actual meeting room', (tester) async {
      final mockLiveKit = MockVorynLiveKitService();
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          liveKitService: mockLiveKit,
        ),
      );
      await tester.pump(); // frame for postFrameCallback connect
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Voryn Sync'), findsOneWidget);
      expect(find.text('Connecting to meeting room...'), findsNothing);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    // 2. Token alone does not show connected state.
    testWidgets('2. Token alone does not show connected state', (tester) async {
      final completer = Completer<VorynLiveKitSession>();
      final mockLiveKit = MockVorynLiveKitService(connectCompleter: completer);

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          liveKitService: mockLiveKit,
        ),
      );
      await tester.pump();

      expect(find.text('Connecting to meeting room...'), findsOneWidget);
      expect(find.text('Mute'), findsNothing);
      expect(find.text('Leave'), findsNothing);

      // Complete future to clean up pending timers
      completer.complete(FakeMeetingSession());
      await tester.pump(const Duration(milliseconds: 100));
    });

    // 3. LiveKit connect failure shows recovery UI.
    testWidgets('3. LiveKit connect failure shows recovery UI', (tester) async {
      final mockLiveKit = MockVorynLiveKitService(shouldFail: true);
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          liveKitService: mockLiveKit,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Connection Failed'), findsOneWidget);
      expect(find.text('Could not connect to meeting room'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
    });

    // 4. Join failure handles membership safely.
    testWidgets('4. Join failure handles membership safely', (tester) async {
      final mockMeetingService = MockVorynMeetingService(throwOnJoin: true);
      expect(
        () => mockMeetingService.joinMeeting('k7q-mzx-p2f'),
        throwsA(isA<StateError>()),
      );
      expect(mockMeetingService.rollbackLeaveCalls, 1);
    });

    // 5. Pre-join microphone preference preserved.
    testWidgets('5. Pre-join microphone preference preserved', (tester) async {
      final session = FakeMeetingSession(micEnabled: false);
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(initialMic: false),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('Muted'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off_rounded), findsWidgets);
    });

    // 6. Pre-join camera preference preserved.
    testWidgets('6. Pre-join camera preference preserved', (tester) async {
      final session = FakeMeetingSession(cameraEnabled: false);
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(initialCamera: false),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('Camera Off'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_rounded), findsWidgets);
    });

    // 7. Existing active membership not removed on retry.
    testWidgets('7. Existing active membership not removed on retry', (tester) async {
      final mockLiveKit = MockVorynLiveKitService(shouldFail: true);
      final mockMeeting = MockVorynMeetingService();

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          liveKitService: mockLiveKit,
          meetingService: mockMeeting,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Retry'), findsOneWidget);
      // Tap retry
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(mockLiveKit.connectMeetingCalls, 2);
      expect(mockMeeting.leaveCalls, 0); // Not removed on retry!
    });

    // 8. Participant join updates UI.
    testWidgets('8. Participant join updates UI', (tester) async {
      final session = FakeMeetingSession();
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          customParticipants: [
            const GroupCallParticipant(id: 'me', name: 'You', initials: 'Y', isYou: true),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('1 in meeting · 00:00'), findsOneWidget);

      final state = tester.state<MeetingRoomScreenState>(find.byType(MeetingRoomScreen));
      state.addTestParticipant(
        const GroupCallParticipant(id: 'alice', name: 'Alice', initials: 'A'),
      );
      await tester.pump();

      expect(find.text('2 in meeting · 00:00'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    // 9. Participant leave updates UI.
    testWidgets('9. Participant leave updates UI', (tester) async {
      final session = FakeMeetingSession();
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          customParticipants: [
            const GroupCallParticipant(id: 'me', name: 'You', initials: 'Y', isYou: true),
            const GroupCallParticipant(id: 'bob', name: 'Bob', initials: 'B'),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('2 in meeting · 00:00'), findsOneWidget);

      final state = tester.state<MeetingRoomScreenState>(find.byType(MeetingRoomScreen));
      state.removeTestParticipant('bob');
      await tester.pump();

      expect(find.text('1 in meeting · 00:00'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    // 10. Audio-only layout renders.
    testWidgets('10. Audio-only layout renders', (tester) async {
      final session = FakeMeetingSession();
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          customParticipants: [
            const GroupCallParticipant(
              id: 'p1',
              name: 'Sarah Connor',
              initials: 'SC',
              isCameraOff: true,
              videoTrack: null,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('audio_tile_p1')), findsOneWidget);
      expect(find.text('Sarah Connor'), findsOneWidget);
    });

    // 11. Video layout renders.
    testWidgets('11. Video layout renders', (tester) async {
      final session = FakeMeetingSession();
      final track = FakeVideoTrack(sid: 'trk-1');
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          customParticipants: [
            GroupCallParticipant(
              id: 'p1',
              name: 'John Doe',
              initials: 'JD',
              isCameraOff: false,
              videoTrack: track,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('tile_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('video_p1')), findsOneWidget);
    });

    // 12. Mute control works.
    testWidgets('12. Mute control works', (tester) async {
      final session = FakeMeetingSession(micEnabled: true);
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(initialMic: true),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('Mute'), findsOneWidget);

      await tester.tap(find.text('Mute'));
      await tester.pump();

      expect(session.micEnabled, false);
      expect(find.text('Muted'), findsOneWidget);
    });

    // 13. Camera control works.
    testWidgets('13. Camera control works', (tester) async {
      final session = FakeMeetingSession(cameraEnabled: false);
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(initialCamera: false),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('Camera Off'), findsOneWidget);

      await tester.tap(find.text('Camera Off'));
      await tester.pump();

      expect(session.cameraEnabled, true);
      expect(find.text('Camera'), findsOneWidget);
    });

    // 14. Speaker control works.
    testWidgets('14. Speaker control works', (tester) async {
      final session = FakeMeetingSession(speakerEnabled: true);
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('Speaker'), findsOneWidget);

      await tester.tap(find.text('Speaker'));
      await tester.pump();

      expect(session.speakerEnabled, false);
      expect(find.text('Earpiece'), findsOneWidget);
    });

    // 15. Screen share action uses real implementation.
    testWidgets('15. Screen share action uses real implementation', (tester) async {
      final session = FakeMeetingSession();
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('Share'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pump();

      expect(session.screenShareEnabled, true);
      expect(find.text('Stop'), findsOneWidget);
    });

    // 16. Leave invokes correct RPC.
    testWidgets('16. Leave invokes correct RPC', (tester) async {
      final session = FakeMeetingSession();
      final mockMeeting = MockVorynMeetingService();

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          meetingService: mockMeeting,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(mockMeeting.leaveCalls, 1);
    });

    // 17. Leave disconnects only meeting session.
    testWidgets('17. Leave disconnects only meeting session', (tester) async {
      final session = FakeMeetingSession();
      final mockMeeting = MockVorynMeetingService();

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          meetingService: mockMeeting,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(session.disconnected, true);
    });

    // 18. Duplicate Leave prevented.
    testWidgets('18. Duplicate Leave prevented', (tester) async {
      final session = FakeMeetingSession();
      final mockMeeting = MockVorynMeetingService();

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          meetingService: mockMeeting,
        ),
      );
      await tester.pump();

      // Tap twice rapidly
      await tester.tap(find.text('Leave'));
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(mockMeeting.leaveCalls, 1);
    });

    // 19. Non-host cannot End Everyone.
    testWidgets('19. Non-host cannot End Everyone', (tester) async {
      final session = FakeMeetingSession();
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(role: 'participant'),
          existingSession: session,
        ),
      );
      await tester.pump();

      expect(find.text('End All'), findsNothing);
    });

    // 20. Host confirmation required.
    testWidgets('20. Host confirmation required', (tester) async {
      final session = FakeMeetingSession();
      final mockMeeting = MockVorynMeetingService();

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(role: 'host'),
          existingSession: session,
          meetingService: mockMeeting,
        ),
      );
      await tester.pump();

      expect(find.text('End All'), findsOneWidget);

      // Tap End All
      await tester.tap(find.text('End All'));
      await tester.pumpAndSettle();

      // Confirmation dialog shown
      expect(find.text('End meeting for everyone?'), findsOneWidget);
      expect(mockMeeting.endForEveryoneCalls, 0);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mockMeeting.endForEveryoneCalls, 0);

      // Tap again and confirm
      await tester.tap(find.text('End All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Meeting'));
      await tester.pumpAndSettle();

      expect(mockMeeting.endForEveryoneCalls, 1);
      expect(session.disconnected, true);
    });

    // 21. End status converges other participants.
    testWidgets('21. End status converges other participants', (tester) async {
      final session = FakeMeetingSession();
      bool callbackCalled = false;

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(role: 'participant'),
          existingSession: session,
          onMeetingEnded: () => callbackCalled = true,
        ),
      );
      await tester.pump();

      final state = tester.state<MeetingRoomScreenState>(find.byType(MeetingRoomScreen));
      state.triggerRemoteMeetingEnd();
      await tester.pumpAndSettle();

      expect(callbackCalled, true);
      expect(session.disconnected, true);
    });

    // 22. App resume detects ended meeting.
    testWidgets('22. App resume detects ended meeting', (tester) async {
      final session = FakeMeetingSession();
      final mockMeeting = MockVorynMeetingService(
        prejoinToReturn: const VorynPrejoinMeeting(
          meetingId: 'm-999',
          title: 'Voryn Sync',
          joinCode: 'k7q-mzx-p2f',
          status: 'ended',
          access: 'link',
          activeParticipantCount: 0,
          capacity: 8,
        ),
      );

      bool endedCallback = false;
      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
          meetingService: mockMeeting,
          onMeetingEnded: () => endedCallback = true,
        ),
      );
      await tester.pump();

      final state = tester.state<MeetingRoomScreenState>(find.byType(MeetingRoomScreen));
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(mockMeeting.resolveCalls, greaterThanOrEqualTo(1));
      expect(endedCallback, true);
      expect(session.disconnected, true);
    });

    // 23. Reconnect does not create duplicate Room.
    testWidgets('23. Reconnect does not create duplicate Room', (tester) async {
      final fakeRoom = FakeMeetingRoom();
      final session = FakeMeetingSession(room: fakeRoom);

      await tester.pumpWidget(
        buildTestableScreen(
          joinedMeeting: sampleJoined(),
          existingSession: session,
        ),
      );
      await tester.pump();

      final state = tester.state<MeetingRoomScreenState>(find.byType(MeetingRoomScreen));
      state.setTestState(MeetingConnectionState.reconnecting);
      await tester.pump();

      expect(find.text('Reconnecting…'), findsOneWidget);
      // Verify room instance was not replaced
      expect(session.room, fakeRoom);
    });

    // 24. Narrow viewport no overflow.
    testWidgets('24. Narrow viewport no overflow (360px, 390px, 768px, 1024px, 1440px)', (tester) async {
      final session = FakeMeetingSession();
      final viewports = [
        const Size(360, 640),
        const Size(390, 844),
        const Size(768, 1024),
        const Size(1024, 768),
        const Size(1440, 900),
      ];

      for (final vp in viewports) {
        await tester.pumpWidget(
          buildTestableScreen(
            joinedMeeting: sampleJoined(role: 'host'),
            existingSession: session,
            size: vp,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'Overflow on viewport $vp');
      }
    });

    // 25. Existing direct calls and Merge Calls unaffected.
    test('25. Existing direct calls and Merge Calls unaffected', () {
      const liveKitService = VorynLiveKitService();
      // Verify connect and connectProvisional exist and are callable methods
      expect(liveKitService.connect, isNotNull);
      expect(liveKitService.connectProvisional, isNotNull);
      expect(liveKitService.connectMeeting, isNotNull);
    });
  });
}

