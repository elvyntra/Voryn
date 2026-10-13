import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../../core/backend/voryn_backend.dart';
import '../../core/notifications/lock_screen_service.dart';
import 'voryn_audio_route_service.dart';
import 'voryn_call_latency_tracker.dart';

class VorynLiveKitSession {
  VorynLiveKitSession(this.room) {
    try {
      room.createListener().on<livekit.LocalTrackUnpublishedEvent>((event) {
        if (event.publication.source == livekit.TrackSource.screenShareVideo) {
          debugPrint('[LIVEKIT_SCREEN_SHARE] Local screen share track unpublished -> deactivate FGS');
          unawaited(LockScreenService.setScreenShareActive(false));
        }
      });
    } catch (_) {}
  }

  final livekit.Room room;
  bool _disconnecting = false;
  bool _disposed = false;
  Future<void>? _teardownFuture;
  Future<void>? _cameraOperation;

  bool get isConnected =>
      !_disposed &&
      !_disconnecting &&
      room.connectionState == livekit.ConnectionState.connected;

  livekit.VideoTrack? get localVideoTrack {
    if (_disposed || _disconnecting) return null;
    final publications = room.localParticipant?.videoTrackPublications ?? [];
    for (final publication in publications) {
      final track = publication.track;
      if (track is livekit.VideoTrack &&
          !publication.muted &&
          publication.source != livekit.TrackSource.screenShareVideo) {
        return track;
      }
    }
    return null;
  }

  livekit.VideoTrack? get localScreenShareTrack {
    if (_disposed || _disconnecting) return null;
    final publications = room.localParticipant?.videoTrackPublications ?? [];
    for (final publication in publications) {
      final track = publication.track;
      if (track is livekit.VideoTrack &&
          !publication.muted &&
          publication.source == livekit.TrackSource.screenShareVideo) {
        return track;
      }
    }
    return null;
  }

  livekit.VideoTrack? get remoteVideoTrack {
    if (_disposed || _disconnecting) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is livekit.VideoTrack &&
            publication.subscribed &&
            !publication.muted &&
            publication.source != livekit.TrackSource.screenShareVideo) {
          return track;
        }
      }
    }
    return null;
  }

  livekit.VideoTrack? get remoteScreenShareTrack {
    if (_disposed || _disconnecting) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track is livekit.VideoTrack &&
            publication.subscribed &&
            !publication.muted &&
            publication.source == livekit.TrackSource.screenShareVideo) {
          return track;
        }
      }
    }
    return null;
  }

  String? get screenSharePresenterName {
    if (localScreenShareTrack != null) return 'You';
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.source == livekit.TrackSource.screenShareVideo &&
            publication.subscribed &&
            !publication.muted &&
            publication.track != null) {
          return participant.name.isNotEmpty
              ? participant.name
              : (participant.identity.isNotEmpty ? participant.identity : 'Presenter');
        }
      }
    }
    return null;
  }

  bool get hasRemoteScreenShare => remoteScreenShareTrack != null;

  bool get hasActiveScreenShare => isScreenShareEnabled || hasRemoteScreenShare;

  bool get isScreenShareEnabled {
    if (_disposed || _disconnecting) return false;
    final publications = room.localParticipant?.videoTrackPublications ?? [];
    for (final publication in publications) {
      if (publication.source == livekit.TrackSource.screenShareVideo &&
          !publication.muted) {
        return true;
      }
    }
    return false;
  }

  Future<void> setMicrophoneEnabled(bool enabled) {
    if (_disposed || _disconnecting) return Future<void>.value();
    return room.localParticipant?.setMicrophoneEnabled(enabled) ??
        Future<void>.value();
  }

  Future<bool> setCameraEnabled(bool enabled) {
    if (_disposed || _disconnecting) return Future<bool>.value(false);
    final previous = _cameraOperation ?? Future<void>.value();
    final completer = Completer<bool>();
    _cameraOperation = completer.future;

    previous
        .then((_) async {
          if (_disposed || _disconnecting) {
            completer.complete(false);
            return;
          }
          try {
            final participant = room.localParticipant;
            if (participant != null) {
              final pubs = participant.videoTrackPublications;
              final hasCamera = pubs.any(
                (p) =>
                    p.source == livekit.TrackSource.camera &&
                    !p.muted &&
                    p.track != null,
              );
              if (enabled != hasCamera || pubs.isEmpty) {
                await participant.setCameraEnabled(enabled);
              }
            }
            completer.complete(true);
          } catch (e) {
            debugPrint('Error toggling camera: $e');
            completer.complete(false);
          }
        })
        .catchError((_) {
          completer.complete(false);
        });

    return completer.future;
  }

  Future<void> setSpeakerEnabled(bool enabled) {
    if (_disposed || _disconnecting) return Future<void>.value();
    return VorynAudioRouteService.instance.setSpeakerEnabled(enabled);
  }

  Future<bool> setScreenShareEnabled(bool enabled) async {
    if (_disposed || _disconnecting) return false;
    final participant = room.localParticipant;
    if (participant == null) return false;

    if (enabled) {
      if (hasRemoteScreenShare) {
        debugPrint('[LIVEKIT_SCREEN_SHARE] Remote participant is already sharing screen.');
        return false;
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Step 1: Prompt user for Android OS screen capture permission first!
        // Android 14+ strictly requires user consent token BEFORE starting/promoting FGS with MEDIA_PROJECTION type.
        try {
          final granted = await webrtc.Helper.requestCapturePermission(fullScreenOnly: true);
          if (!granted) {
            debugPrint('[LIVEKIT_SCREEN_SHARE] User cancelled or denied screen capture prompt.');
            return false;
          }
        } catch (e) {
          debugPrint('[LIVEKIT_SCREEN_SHARE] requestCapturePermission error: $e');
        }
      }
      await LockScreenService.setScreenShareActive(true);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      try {
        final pub = await participant.setScreenShareEnabled(true);
        if (pub == null) {
          debugPrint('[LIVEKIT_SCREEN_SHARE] Screen share returned null publication');
          await LockScreenService.setScreenShareActive(false);
          return false;
        }
        debugPrint('[LIVEKIT_SCREEN_SHARE] Screen share successfully enabled and verified: ${pub.sid}');
        return true;
      } catch (e) {
        debugPrint('[LIVEKIT_SCREEN_SHARE] Error enabling screen share: $e');
        await LockScreenService.setScreenShareActive(false);
        return false;
      }
    } else {
      try {
        await participant.setScreenShareEnabled(false);
      } catch (e) {
        debugPrint('[LIVEKIT_SCREEN_SHARE] Error disabling screen share: $e');
      } finally {
        await LockScreenService.setScreenShareActive(false);
      }
      return true;
    }
  }

  bool _isHeld = false;
  bool get isHeld => _isHeld;

  /// Holds the session by muting local mic and suppressing remote audio/video tracks.
  Future<void> hold() async {
    if (_disposed || _disconnecting || _isHeld) return;
    _isHeld = true;

    var remoteAudioCount = 0;
    // 1. Mute local mic
    try {
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}

    // 2. Mute local camera
    try {
      await room.localParticipant?.setCameraEnabled(false);
    } catch (_) {}

    // 3. Silence remote audio & video tracks
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        remoteAudioCount++;
        try {
          pub.track?.mediaStreamTrack.enabled = false;
          await pub.disable();
        } catch (_) {}
      }
      for (final pub in participant.videoTrackPublications) {
        try {
          pub.track?.mediaStreamTrack.enabled = false;
          await pub.disable();
        } catch (_) {}
      }
    }

    debugPrint(
      '[LIVEKIT_HOLD] callId=${room.name} remoteAudioTrackCount=$remoteAudioCount held=true',
    );
  }

  /// Resumes the session by restoring remote audio/video tracks and restoring local mic/camera.
  Future<void> resume({
    bool restoreMic = true,
    bool restoreCamera = false,
  }) async {
    if (_disposed || _disconnecting || !_isHeld) return;
    _isHeld = false;

    var remoteAudioRestored = 0;
    // 1. Restore remote audio & video tracks
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        remoteAudioRestored++;
        try {
          pub.track?.mediaStreamTrack.enabled = true;
          await pub.enable();
        } catch (_) {}
      }
      for (final pub in participant.videoTrackPublications) {
        try {
          pub.track?.mediaStreamTrack.enabled = true;
          await pub.enable();
        } catch (_) {}
      }
    }

    // 2. Restore local mic only if it was enabled before hold
    if (restoreMic) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (_) {}
    }

    // 3. Restore local camera only if it was enabled before hold
    if (restoreCamera) {
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (_) {}
    }

    debugPrint(
      '[LIVEKIT_RESUME] callId=${room.name} remoteAudioRestored=$remoteAudioRestored micRestored=$restoreMic cameraRestored=$restoreCamera',
    );
  }

  Future<void> disconnect() {
    return _teardownFuture ??= _performDisconnect();
  }

  Future<void> _performDisconnect() async {
    if (_disposed) return;
    _disconnecting = true;
    try {
      if (room.connectionState != livekit.ConnectionState.disconnected) {
        await room.disconnect();
      }
    } catch (_) {
      // Best effort disconnect
    } finally {
      if (!_disposed) {
        _disposed = true;
        try {
          await room.dispose();
        } catch (_) {}
      }
      try {
        await LockScreenService.setScreenShareActive(false);
      } catch (_) {}
    }
  }
}

class VorynLiveKitService {
  const VorynLiveKitService();

  Future<VorynLiveKitSession> connect({
    required String callId,
    required bool video,
    VorynCallLatencyTracker? latencyTracker,
  }) async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentSession == null) {
      throw const VorynLiveKitException('Sign in before joining a call.');
    }

    await latencyTracker?.stage('livekit_token_request');
    dynamic response;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        response = await client.functions.invoke(
          'livekit-token',
          body: {'callId': callId},
        );
        final data = response.data;
        if (data is Map && data['token'] is String && (data['token'] as String).isNotEmpty) {
          break;
        }
      } catch (e) {
        if (attempt == 3) rethrow;
      }
      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    await latencyTracker?.stage('livekit_token_done');

    final data = response?.data;
    if (data is! Map) {
      throw const VorynLiveKitException('The call room is unavailable.');
    }
    final url = data['url'];
    final token = data['token'];
    if (url is! String || token is! String || url.isEmpty || token.isEmpty) {
      throw VorynLiveKitException(
        data['error'] as String? ?? 'The call room is unavailable.',
      );
    }

    final room = livekit.Room();
    try {
      await latencyTracker?.stage('room_connect_start');
      await room.connect(url, token);
      await latencyTracker?.stage('room_connected');
      await latencyTracker?.stage('signaling_connected');
      await latencyTracker?.stage('ice_connected');

      await room.localParticipant?.setMicrophoneEnabled(true);
      await latencyTracker?.stage('local_track_published');
      await latencyTracker?.stage('local_audio_ready');

      await VorynAudioRouteService.instance.setDefaultAudioRoute(
        isVideo: video,
      );

      if (video) await room.localParticipant?.setCameraEnabled(true);

      if (room.remoteParticipants.isNotEmpty) {
        await latencyTracker?.stage('remote_participant_joined');
        await latencyTracker?.stage('remote_audio_subscribed');
      }

      return VorynLiveKitSession(room);
    } catch (_) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  /// Connects provisionally to the surviving conference room during merge.
  /// STRICT INVARIANT: Media-silent!
  /// Does NOT enable microphone, camera, or speaker audio route.
  Future<VorynLiveKitSession> connectProvisional({
    required String primaryCallId,
    required String mergeOperationId,
  }) async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentSession == null) {
      throw const VorynLiveKitException('Sign in before joining a call.');
    }

    dynamic response;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        response = await client.functions.invoke(
          'livekit-token',
          body: {
            'callId': primaryCallId,
            'mergeOperationId': mergeOperationId,
          },
        );
        final data = response.data;
        if (data is Map &&
            data['token'] is String &&
            (data['token'] as String).isNotEmpty) {
          break;
        }
      } catch (e) {
        if (attempt == 3) rethrow;
      }
      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    final data = response?.data;
    if (data is! Map) {
      throw const VorynLiveKitException('The conference room is unavailable.');
    }
    final url = data['url'];
    final token = data['token'];
    if (url is! String || token is! String || url.isEmpty || token.isEmpty) {
      throw VorynLiveKitException(
        data['error'] as String? ?? 'The conference room is unavailable.',
      );
    }

    final room = livekit.Room();
    try {
      await room.connect(url, token);
      // Provisional session is media-silent: no mic, no camera, no audio route
      return VorynLiveKitSession(room);
    } catch (_) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  /// Connects to a verified LiveKit meeting room.
  /// Respects pre-join preferences for microphone and camera.
  Future<VorynLiveKitSession> connectMeeting({
    required String url,
    required String token,
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    final room = livekit.Room();
    try {
      await room.connect(url, token);

      if (initialMic) {
        try {
          await room.localParticipant?.setMicrophoneEnabled(true);
        } catch (_) {}
      } else {
        try {
          await room.localParticipant?.setMicrophoneEnabled(false);
        } catch (_) {}
      }

      if (initialCamera) {
        try {
          await room.localParticipant?.setCameraEnabled(true);
        } catch (_) {}
      } else {
        try {
          await room.localParticipant?.setCameraEnabled(false);
        } catch (_) {}
      }

      return VorynLiveKitSession(room);
    } catch (_) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
      rethrow;
    }
  }
}

class VorynLiveKitException implements Exception {
  const VorynLiveKitException(this.message);
  final String message;
}
