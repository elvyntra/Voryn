import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

/// Cross-platform audio route service.
/// Isolates mobile-specific audio management (earpiece, speaker) from Web.
abstract class VorynAudioRouteService {
  static final VorynAudioRouteService instance = _create();

  static VorynAudioRouteService _create() {
    if (kIsWeb) {
      return const _WebAudioRouteService();
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const _AndroidAudioRouteService();
      case TargetPlatform.iOS:
        return const _IOSAudioRouteService();
      default:
        return const _WebAudioRouteService();
    }
  }

  bool get isEarpieceSupported;

  Future<void> setDefaultAudioRoute({required bool isVideo});

  Future<void> setSpeakerEnabled(bool enabled);
}

class _AndroidAudioRouteService implements VorynAudioRouteService {
  const _AndroidAudioRouteService();

  @override
  bool get isEarpieceSupported => true;

  @override
  Future<void> setDefaultAudioRoute({required bool isVideo}) async {
    try {
      await livekit.AudioManager.instance.setSpeakerOutputPreferred(isVideo);
      debugPrint('[AUDIO_ROUTE] requested=${isVideo ? "speaker" : "earpiece"}');
    } catch (e) {
      debugPrint('[AUDIO_ROUTE] error setting default route: $e');
    }
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    try {
      await livekit.AudioManager.instance.setSpeakerOutputPreferred(enabled);
      debugPrint('[AUDIO_ROUTE] requested=${enabled ? "speaker" : "earpiece"}');
    } catch (e) {
      debugPrint('[AUDIO_ROUTE] error setting speaker enabled: $e');
    }
  }
}

class _IOSAudioRouteService implements VorynAudioRouteService {
  const _IOSAudioRouteService();

  @override
  bool get isEarpieceSupported => true;

  @override
  Future<void> setDefaultAudioRoute({required bool isVideo}) async {
    try {
      await livekit.AudioManager.instance.setSpeakerOutputPreferred(isVideo);
    } catch (e) {
      debugPrint('[AUDIO_ROUTE] iOS error setting default route: $e');
    }
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    try {
      await livekit.AudioManager.instance.setSpeakerOutputPreferred(enabled);
    } catch (e) {
      debugPrint('[AUDIO_ROUTE] iOS error setting speaker: $e');
    }
  }
}

class _WebAudioRouteService implements VorynAudioRouteService {
  const _WebAudioRouteService();

  @override
  bool get isEarpieceSupported => false;

  @override
  Future<void> setDefaultAudioRoute({required bool isVideo}) async {
    // Web uses browser default audio output (speakers/headphones).
    // Graceful no-op.
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    // Browser manages output device via WebRTC / standard HTML media elements.
    // Graceful no-op.
  }
}
