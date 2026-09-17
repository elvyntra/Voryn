import 'dart:async';
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../../core/backend/voryn_backend.dart';

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
    return livekit.AudioManager.instance.setSpeakerOutputPreferred(enabled);
  }

  Future<void> setScreenShareEnabled(bool enabled) async {
    if (_disposed || _disconnecting) return;
    try {
      await room.localParticipant?.setScreenShareEnabled(enabled);
    } catch (_) {}
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
      // Allow in-flight disconnect events (LocalTrackUnpublishedEvent, RoomDisconnectedEvent)
      // to dispatch before disposing the room emitter.
      await Future<void>.delayed(const Duration(milliseconds: 50));
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
  }) async {
    final client = VorynBackend.client;
    if (client == null || client.auth.currentSession == null) {
      throw const VorynLiveKitException('Sign in before joining a call.');
    }

    final response = await client.functions.invoke(
      'livekit-token',
      body: {'callId': callId},
    );
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
      await room.connect(url, token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
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
