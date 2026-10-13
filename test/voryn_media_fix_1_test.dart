// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:livekit_client/src/track/video_track_view_registration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voryn/features/calling/group_call_screen.dart';
import 'package:voryn/features/calling/voryn_livekit_service.dart';
import 'package:voryn/features/calling/widgets/video_pip.dart';
import 'package:voryn/features/meetings/meeting_room_screen.dart';
import 'package:voryn/features/meetings/models/meeting_models.dart';

class FakeVideoTrack extends Fake implements livekit.VideoTrack {
  @override
  final String? sid;

  FakeVideoTrack({this.sid});

  @override
  bool get muted => false;

  @override
  VideoTrackViewRegistration addViewRegistration({
    livekit.AdaptiveStreamPixelDensity pixelDensity =
        livekit.AdaptiveStreamPixelDensity.auto,
  }) =>
      VideoTrackViewRegistration(pixelDensity: pixelDensity);

  @override
  void removeViewRegistration(VideoTrackViewRegistration registration) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeMediaMeetingSession implements VorynLiveKitSession {
  bool micEnabled;
  bool cameraEnabled;
  bool speakerEnabled;
  bool screenShareEnabled;
  bool disconnected;
  livekit.VideoTrack? remoteScreenTrack;
  String? presenterName;

  FakeMediaMeetingSession({
    this.micEnabled = true,
    this.cameraEnabled = false,
    this.speakerEnabled = true,
    this.screenShareEnabled = false,
    this.disconnected = false,
    this.remoteScreenTrack,
    this.presenterName,
  });

  @override
  bool get isConnected => !disconnected;

  @override
  bool get isHeld => false;

  @override
  livekit.VideoTrack? get localVideoTrack =>
      cameraEnabled ? FakeVideoTrack(sid: 'local_cam') : null;

  @override
  livekit.VideoTrack? get localScreenShareTrack =>
      screenShareEnabled ? FakeVideoTrack(sid: 'local_screen') : null;

  @override
  livekit.VideoTrack? get remoteVideoTrack => null;

  @override
  livekit.VideoTrack? get remoteScreenShareTrack => remoteScreenTrack;

  @override
  String? get screenSharePresenterName => presenterName;

  @override
  bool get hasRemoteScreenShare => remoteScreenTrack != null;

  @override
  bool get hasActiveScreenShare => screenShareEnabled || hasRemoteScreenShare;

  @override
  bool get isScreenShareEnabled => screenShareEnabled;

  @override
  livekit.Room get room => throw UnimplementedError('Mock LiveKit room');

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
    if (enabled && hasRemoteScreenShare) return false;
    screenShareEnabled = enabled;
    return true;
  }

  @override
  Future<void> disconnect() async => disconnected = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Checkpoint VORYN-MEDIA-FIX-1: Video, PiP & Meeting Stabilization', () {
    testWidgets('Part A: VideoPip smoothly tracks pan gesture and clamps to bounds', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      Offset? reportedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                VideoPip(
                  videoTrack: null,
                  label: 'You',
                  userInitials: 'YU',
                  controlsVisible: true,
                  onOffsetChanged: (offset) => reportedOffset = offset,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pipFinder = find.byType(VideoPip);
      expect(pipFinder, findsOneWidget);

      final initialRect = tester.getRect(pipFinder);

      // Drag up and to the left
      await tester.drag(pipFinder, const Offset(-50, -100));
      await tester.pumpAndSettle();

      final updatedRect = tester.getRect(pipFinder);
      expect(updatedRect.top, lessThan(initialRect.top));
      expect(reportedOffset, isNotNull);

      // Drag offscreen to test clamping
      await tester.drag(pipFinder, const Offset(-1000, -1000));
      await tester.pumpAndSettle();

      final clampedRect = tester.getRect(pipFinder);
      expect(clampedRect.left, greaterThanOrEqualTo(0.0));
      expect(clampedRect.top, greaterThanOrEqualTo(0.0));
    });

    testWidgets('Part A: VideoPip tap triggers callback for swap', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                VideoPip(
                  videoTrack: null,
                  label: 'You',
                  userInitials: 'YU',
                  controlsVisible: true,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(VideoPip));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('Part B: MeetingRoomScreen tap-to-hide toggles controls and expands stage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = FakeMediaMeetingSession();
      const joined = VorynJoinedMeeting(
        meetingId: 'meet-media-001',
        title: 'Stabilization Meeting',
        livekitRoomName: 'voryn-room-123',
        role: 'host',
        status: 'active',
        access: 'public',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingRoomScreen(
            joinedMeeting: joined,
            existingSession: session,
            customParticipants: const [
              GroupCallParticipant(id: 'me', name: 'You', initials: 'YU', isYou: true),
              GroupCallParticipant(id: 'remote1', name: 'Alice', initials: 'AL'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Controls initially visible
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);

      // Tap stage to hide controls
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Persistent pill should now appear
      expect(find.byKey(const Key('persistent_status_pill')), findsOneWidget);

      // Tap again to restore controls
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('Part B: 2-participant meeting layout button toggles between split and floating PiP', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = FakeMediaMeetingSession();
      final track = FakeVideoTrack(sid: 'trk-remote');
      const joined = VorynJoinedMeeting(
        meetingId: 'meet-media-002',
        title: 'Two Person Meeting',
        livekitRoomName: 'voryn-room-123',
        role: 'participant',
        status: 'active',
        access: 'public',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingRoomScreen(
            joinedMeeting: joined,
            existingSession: session,
            customParticipants: [
              const GroupCallParticipant(id: 'me', name: 'You', initials: 'YU', isYou: true),
              GroupCallParticipant(id: 'remote1', name: 'Bob', initials: 'BO', videoTrack: track),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Layout button exists in top bar for 2 participants
      final layoutBtn = find.byKey(const Key('layout_toggle_button'));
      expect(layoutBtn, findsOneWidget);

      // Initially in split view (no VideoPip)
      expect(find.byType(VideoPip), findsNothing);

      // Toggle to PiP mode
      await tester.tap(layoutBtn);
      await tester.pumpAndSettle();

      // Now VideoPip is present!
      expect(find.byType(VideoPip), findsOneWidget);

      // Toggle back to split view
      await tester.tap(layoutBtn);
      await tester.pumpAndSettle();

      expect(find.byType(VideoPip), findsNothing);
    });

    testWidgets('Part C: Screen sharing renders screen share stage when active', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final screenTrack = FakeVideoTrack(sid: 'remote_screen_track');
      final session = FakeMediaMeetingSession(
        remoteScreenTrack: screenTrack,
        presenterName: 'Sarah Connor',
      );
      const joined = VorynJoinedMeeting(
        meetingId: 'meet-media-003',
        title: 'Screen Sharing Demo',
        livekitRoomName: 'voryn-room-123',
        role: 'participant',
        status: 'active',
        access: 'public',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingRoomScreen(
            joinedMeeting: joined,
            existingSession: session,
            customParticipants: const [
              GroupCallParticipant(id: 'me', name: 'You', initials: 'YU', isYou: true),
              GroupCallParticipant(id: 'remote1', name: 'Sarah Connor', initials: 'SC'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen share banner should be displayed
      expect(find.text('Sarah Connor is sharing screen'), findsOneWidget);
    });

    testWidgets('Part C: Screen share toggle rejects when remote is already presenting', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final screenTrack = FakeVideoTrack(sid: 'remote_screen_track');
      final session = FakeMediaMeetingSession(
        remoteScreenTrack: screenTrack,
        presenterName: 'Sarah Connor',
      );
      const joined = VorynJoinedMeeting(
        meetingId: 'meet-media-004',
        title: 'One Presenter Rule',
        livekitRoomName: 'voryn-room-123',
        role: 'participant',
        status: 'active',
        access: 'public',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MeetingRoomScreen(
            joinedMeeting: joined,
            existingSession: session,
            customParticipants: const [
              GroupCallParticipant(id: 'me', name: 'You', initials: 'YU', isYou: true),
              GroupCallParticipant(id: 'remote1', name: 'Sarah Connor', initials: 'SC'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap share button
      final shareBtn = find.text('Share');
      expect(shareBtn, findsOneWidget);

      await tester.tap(shareBtn);
      await tester.pump();

      // Should show SnackBar that someone else is already sharing
      expect(find.text('Someone else is already sharing screen'), findsOneWidget);
    });
  });
}
