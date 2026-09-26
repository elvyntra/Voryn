import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../../core/backend/voryn_backend.dart';
import 'voryn_audio_route_service.dart';
import 'voryn_call_latency_tracker.dart';

class VorynLiveKitSession {
  VorynLiveKitSession(this.room);

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
      if (track is livekit.VideoTrack && !publication.muted) return track;
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
            !publication.muted) {
          return track;
        }
      }
    }
    return null;
  }

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

  Future<void> setCameraEnabled(bool enabled) {
    if (_disposed || _disconnecting) return Future<void>.value();
    final previous = _cameraOperation ?? Future<void>.value();
    final completer = Completer<void>();
    _cameraOperation = completer.future;

    previous
        .then((_) async {
          if (_disposed || _disconnecting) {
            completer.complete();
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
          } catch (_) {
          } finally {
            completer.complete();
          }
        })
        .catchError((_) {
          completer.complete();
        });

    return completer.future;
  }

  Future<void> setSpeakerEnabled(bool enabled) {
    if (_disposed || _disconnecting) return Future<void>.value();
    return VorynAudioRouteService.instance.setSpeakerEnabled(enabled);
  }

  Future<void> setScreenShareEnabled(bool enabled) async {
    if (_disposed || _disconnecting) return;
    try {
      await room.localParticipant?.setScreenShareEnabled(enabled);
    } catch (_) {}
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

    await latencyTracker?.stage('livekit_token_start');
    final response = await client.functions.invoke(
      'livekit-token',
      body: {'callId': callId},
    );
    await latencyTracker?.stage('livekit_token_done');

    final data = response.data;
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
      await latencyTracker?.stage('livekit_connect_start');
      await room.connect(url, token);
      await latencyTracker?.stage('signaling_connected');
      await latencyTracker?.stage('ice_connected');

      await room.localParticipant?.setMicrophoneEnabled(true);
      await latencyTracker?.stage('local_audio_ready');

      await VorynAudioRouteService.instance.setDefaultAudioRoute(
        isVideo: video,
      );

      if (video) await room.localParticipant?.setCameraEnabled(true);

      if (room.remoteParticipants.isNotEmpty) {
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
}

class VorynLiveKitException implements Exception {
  const VorynLiveKitException(this.message);
  final String message;
}
