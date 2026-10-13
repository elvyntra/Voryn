import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/core/theme/voryn_theme.dart';
import 'package:voryn/features/calling/group_call_screen.dart';
import 'package:voryn/features/calling/multi_call_coordinator.dart';
import 'package:voryn/features/calling/voryn_livekit_service.dart';
import 'package:voryn/features/calling/widgets/call_top_bar.dart';

class FakeVideoTrack extends Fake implements livekit.VideoTrack {
  @override
  final String? sid;

  FakeVideoTrack({this.sid});
}

class FakeConferenceSession implements VorynLiveKitSession {
  bool micEnabled;
  bool cameraEnabled;
  bool speakerEnabled;
  bool held;
  bool disconnected;

  FakeConferenceSession({
    this.micEnabled = true,
    this.cameraEnabled = false,
    this.speakerEnabled = false,
    this.held = false,
    this.disconnected = false,
  });

  @override
  bool get isConnected => !disconnected;

  @override
  bool get isHeld => held;

  @override
  livekit.VideoTrack? get localVideoTrack => null;

  @override
  livekit.VideoTrack? get remoteVideoTrack => null;

  @override
  bool get isScreenShareEnabled => false;

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
  livekit.Room get room => throw UnimplementedError('Mock test room');

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
  Future<bool> setScreenShareEnabled(bool enabled) async => true;

  @override
  Future<void> disconnect() async => disconnected = true;
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

  List<GroupCallParticipant> makeThreeParticipants({
    bool withVideo = false,
    livekit.VideoTrack? localTrack,
    livekit.VideoTrack? remoteTrack,
  }) {
    return [
      GroupCallParticipant(
        id: 'me',
        name: 'You',
        initials: 'YO',
        isYou: true,
        isMuted: false,
        isCameraOff: !withVideo,
        videoTrack: withVideo ? (localTrack ?? FakeVideoTrack(sid: 'trk-local')) : null,
      ),
      GroupCallParticipant(
        id: 'p2',
        name: 'Alice',
        initials: 'AL',
        isYou: false,
        isMuted: false,
        isCameraOff: !withVideo,
        videoTrack: withVideo ? (remoteTrack ?? FakeVideoTrack(sid: 'trk-remote-1')) : null,
      ),
      GroupCallParticipant(
        id: 'p3',
        name: 'Bob',
        initials: 'BO',
        isYou: false,
        isMuted: true,
        isCameraOff: true,
      ),
    ];
  }

  void setupViewport(
    WidgetTester tester, {
    Size physicalSize = const Size(1080, 2400),
    double dpr = 2.5,
  }) {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = dpr;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget buildConferenceTestApp({
    required Widget child,
  }) {
    return MaterialApp(
      theme: VorynTheme.dark,
      home: child,
    );
  }

  group('Checkpoint MC-3 — Merged Conference UI Tests', () {
    testWidgets('1. 3-person conference renders', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-101',
            title: 'Conference',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Conference'), findsWidgets);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('2. Participant count correct', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-102',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CallTopBar),
          matching: find.textContaining('3 in call'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('3. Audio-only layout renders', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants(withVideo: false);
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-103',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      // Audio tiles should be rendered for each participant
      expect(find.byKey(const ValueKey('audio_tile_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('audio_tile_p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('audio_tile_p3')), findsOneWidget);
      // No VideoTrackSurface in audio-only
      expect(find.byType(ConferenceVideoTrackSurface), findsNothing);
    });

    testWidgets('4. Video grid renders', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants(withVideo: true);
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-104',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      // Video layout tiles rendered
      expect(find.byKey(const ValueKey('tile_me')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile_p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile_p3')), findsOneWidget);
    });

    testWidgets('5. Local video mirrors correctly', (tester) async {
      setupViewport(tester);
      final localTrack = FakeVideoTrack(sid: 'trk-local-mirror');
      final participants = makeThreeParticipants(
        withVideo: true,
        localTrack: localTrack,
      );
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-105',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      final localSurfaceFinder = find.byKey(const ValueKey('video_me'));
      expect(localSurfaceFinder, findsOneWidget);

      final localSurface =
          tester.widget<ConferenceVideoTrackSurface>(localSurfaceFinder);
      expect(localSurface.mirrorMode, livekit.VideoViewMirrorMode.mirror);
    });

    testWidgets('6. Remote video not mirrored', (tester) async {
      setupViewport(tester);
      final remoteTrack = FakeVideoTrack(sid: 'trk-remote-nomirror');
      final participants = makeThreeParticipants(
        withVideo: true,
        remoteTrack: remoteTrack,
      );
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-106',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      final remoteSurfaceFinder = find.byKey(const ValueKey('video_p2'));
      expect(remoteSurfaceFinder, findsOneWidget);

      final remoteSurface =
          tester.widget<ConferenceVideoTrackSurface>(remoteSurfaceFinder);
      expect(remoteSurface.mirrorMode, livekit.VideoViewMirrorMode.off);
    });

    testWidgets('7. Participant join updates count', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-107',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CallTopBar),
          matching: find.textContaining('3 in call'),
        ),
        findsOneWidget,
      );

      // Participant Charlie joins
      final state = tester.state<GroupCallScreenState>(find.byType(GroupCallScreen));
      state.addTestParticipant(
        const GroupCallParticipant(
          id: 'p4',
          name: 'Charlie',
          initials: 'CH',
          isYou: false,
          isMuted: false,
          isCameraOff: true,
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CallTopBar),
          matching: find.textContaining('4 in call'),
        ),
        findsOneWidget,
      );
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('8. Participant leave updates count', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-108',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CallTopBar),
          matching: find.textContaining('3 in call'),
        ),
        findsOneWidget,
      );

      // Alice leaves
      final state = tester.state<GroupCallScreenState>(find.byType(GroupCallScreen));
      state.removeTestParticipant('p2');
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(CallTopBar),
          matching: find.textContaining('2 in call'),
        ),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('9. Participant list opens', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-109',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      // Tap People button
      final peopleBtn = find.text('People');
      expect(peopleBtn, findsOneWidget);
      await tester.tap(peopleBtn);
      await tester.pumpAndSettle();

      // Modal bottom sheet opens
      expect(find.text('Participants (3)'), findsOneWidget);
      expect(find.text('Add Participant'), findsOneWidget);
    });

    testWidgets('10. Participant privacy fields hidden', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-110',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      // Open participant sheet
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();

      // Privacy verification: no email, phone, or raw UUIDs visible
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('+91'), findsNothing);
      expect(find.textContaining('6f7f1ca3'), findsNothing);
    });

    testWidgets('11. Leave Call visible', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-111',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('12. End Call for Everyone permission-gated', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();

      // Non-initiator: End All is hidden
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-112',
            participants: participants,
            existingSession: FakeConferenceSession(),
            isInitiator: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('End All'), findsNothing);

      // Initiator: End All is present and displays confirmation dialog
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-112-init',
            participants: participants,
            existingSession: FakeConferenceSession(),
            isInitiator: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('End All'), findsOneWidget);

      await tester.tap(find.text('End All'));
      await tester.pumpAndSettle();

      // Confirmation dialog shown
      expect(find.text('End Call for Everyone?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('End for Everyone'), findsOneWidget);
    });

    testWidgets('13. Merge transition preserves timer', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-113',
            participants: participants,
            existingSession: FakeConferenceSession(),
            initialDuration: const Duration(minutes: 5, seconds: 22),
          ),
        ),
      );
      await tester.pump();

      // Initial duration preserved from pre-merge active call
      expect(find.textContaining('05:22'), findsWidgets);
    });

    testWidgets('14. No duplicate conference route', (tester) async {
      final coordinator = MultiCallCoordinator.instance;
      coordinator.markConference('conf-114', isInitiator: true);

      expect(coordinator.isConference('conf-114'), isTrue);
      // Marking again is idempotent
      coordinator.markConference('conf-114', isInitiator: true);
      expect(coordinator.isConference('conf-114'), isTrue);
    });

    testWidgets('15. Reconnecting indicator remains visible', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      final disconnectedSession = FakeConferenceSession(disconnected: true);

      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-115',
            participants: participants,
            existingSession: disconnectedSession,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Reconnecting…'), findsWidgets);
    });

    testWidgets('16. Controls hide/show', (tester) async {
      setupViewport(tester);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-116',
            participants: participants,
            existingSession: FakeConferenceSession(),
          ),
        ),
      );
      await tester.pump();

      // Controls initially visible
      final topBarFinder = find.byType(CallTopBar);
      expect(topBarFinder, findsOneWidget);

      final topOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: topBarFinder, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(topOpacity.opacity, 1.0);

      // Tap main stage
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      // Controls now hidden
      final hiddenTopOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: topBarFinder, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(hiddenTopOpacity.opacity, 0.0);

      // Tap again to restore controls
      await tester.tapAt(const Offset(200, 300));
      await tester.pumpAndSettle();

      final restoredOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: topBarFinder, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(restoredOpacity.opacity, 1.0);
    });

    testWidgets('17. Narrow viewport no overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final participants = makeThreeParticipants(withVideo: true);
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-117',
            participants: participants,
            existingSession: FakeConferenceSession(),
            isInitiator: true,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('18. Tablet layout no overflow', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final participants = makeThreeParticipants(withVideo: true);
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-118',
            participants: participants,
            existingSession: FakeConferenceSession(),
            isInitiator: true,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('19. Desktop layout no overflow', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final participants = makeThreeParticipants(withVideo: true);
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-119',
            participants: participants,
            existingSession: FakeConferenceSession(),
            isInitiator: true,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('20. Existing call controls still functional', (tester) async {
      setupViewport(tester);
      final fakeSession = FakeConferenceSession(micEnabled: true, cameraEnabled: true);
      final participants = makeThreeParticipants();
      await tester.pumpWidget(
        buildConferenceTestApp(
          child: GroupCallScreen(
            callId: 'conf-120',
            participants: participants,
            existingSession: fakeSession,
          ),
        ),
      );
      await tester.pump();

      // Mute toggle
      final muteBtn = find.text('Mute');
      expect(muteBtn, findsOneWidget);
      await tester.tap(muteBtn);
      await tester.pump();

      expect(find.text('Muted'), findsOneWidget);
      expect(fakeSession.micEnabled, isFalse);

      // Camera toggle
      final camBtn = find.text('Camera');
      expect(camBtn, findsOneWidget);
      await tester.tap(camBtn);
      await tester.pump();

      expect(find.text('Camera Off'), findsOneWidget);
      expect(fakeSession.cameraEnabled, isFalse);
    });
  });
}

