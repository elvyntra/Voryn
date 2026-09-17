import 'package:flutter/material.dart';

import '../connect/mock_voryn_state.dart';
import 'active_audio_call_screen.dart';
import 'active_video_call_screen.dart';
import 'voryn_call_service.dart';

class CallRequestScreen extends StatefulWidget {
  const CallRequestScreen({
    super.key,
    required this.user,
    required this.video,
    this.existingCallId,
  });

  final VorynMockUser user;
  final bool video;
  final String? existingCallId;

  @override
  State<CallRequestScreen> createState() => _CallRequestScreenState();
}

class _CallRequestScreenState extends State<CallRequestScreen> {
  String? _callId;
  String? _error;
  bool _initiating = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingCallId != null) {
      _callId = widget.existingCallId;
    } else {
      _initiate();
    }
  }

  Future<void> _initiate() async {
    setState(() {
      _initiating = true;
      _error = null;
    });

    final candidate = widget.user.backendUid ?? widget.user.id;
    final res = await const VorynCallService().start(
      vorynId: candidate,
      video: widget.video,
    );

    if (!mounted) return;
    if (res.isSuccess && res.id != null) {
      setState(() {
        _callId = res.id;
        _initiating = false;
      });
    } else {
      setState(() {
        _error = res.error ?? 'Could not start call.';
        _initiating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_callId != null) {
      if (widget.video) {
        return ActiveVideoCallScreen(callId: _callId!, user: widget.user);
      }
      return ActiveAudioCallScreen(callId: _callId!, user: widget.user);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_initiating) ...[
                  const CircularProgressIndicator(color: Color(0xFF22C55E)),
                  const SizedBox(height: 24),
                  Text(
                    'Calling ${widget.user.displayName}…',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ] else if (_error != null) ...[
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go back'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
