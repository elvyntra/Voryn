import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/voryn_backend.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_button.dart';
import 'models/meeting_models.dart';
import 'services/voryn_meeting_service.dart';
import 'services/voryn_meeting_link_service.dart';
import 'meetings_screen.dart';

/// Direct route entry screen for `/m/:code` web URLs and deep links.
class MeetingDirectLinkScreen extends StatefulWidget {
  const MeetingDirectLinkScreen({
    super.key,
    required this.rawCode,
    this.meetingService,
    this.isAuthenticated,
  });

  final String rawCode;
  final VorynMeetingService? meetingService;
  final bool? isAuthenticated;

  @override
  State<MeetingDirectLinkScreen> createState() => _MeetingDirectLinkScreenState();
}

class _MeetingDirectLinkScreenState extends State<MeetingDirectLinkScreen> {
  late final VorynMeetingService _service = widget.meetingService ?? VorynMeetingService.instance;

  bool _isLoading = true;
  String? _parseError;
  String? _resolveError;
  VorynPrejoinMeeting? _prejoinMeeting;
  bool _isHost = false;
  bool _requiresLogin = false;
  String? _normalizedCode;

  @override
  void initState() {
    super.initState();
    _processLink();
  }

  Future<void> _processLink() async {
    setState(() {
      _isLoading = true;
      _parseError = null;
      _resolveError = null;
      _requiresLogin = false;
    });

    // 1. Central Link Validation
    final parseResult = VorynMeetingLinkService.parse(widget.rawCode);
    if (!parseResult.isSuccess || parseResult.link == null) {
      setState(() {
        _isLoading = false;
        _parseError = parseResult.errorMessage ?? 'Invalid meeting link format.';
      });
      return;
    }

    final code = parseResult.link!.joinCode;
    _normalizedCode = code;

    // 2. Authentication Handoff Check
    final isAuthed = widget.isAuthenticated ?? (VorynBackend.client?.auth.currentUser != null);
    if (!isAuthed) {
      // Preserve pending meeting intent for authentication restoration
      VorynMeetingLinkService.setPendingIntent(code);
      setState(() {
        _isLoading = false;
        _requiresLogin = true;
      });
      return;
    }

    // 3. Read-Only Pre-Join Resolution
    // MUST NOT call join_voryn_meeting or livekit-token here
    try {
      final prejoin = await _service.resolveMeetingForPrejoin(code);
      if (!mounted) return;

      if (prejoin == null) {
        setState(() {
          _isLoading = false;
          _resolveError = 'Meeting not found, has already ended, or is restricted to invited attendees.';
        });
        return;
      }

      if (prejoin.status == 'ended' || prejoin.status == 'cancelled') {
        setState(() {
          _isLoading = false;
          _resolveError = 'This meeting has already ${prejoin.status}.';
        });
        return;
      }

      // Check if current user is the meeting host
      bool hostCheck = false;
      try {
        final myMeetings = await _service.listMyMeetings();
        final me = myMeetings.where((m) => m.id == prejoin.meetingId).firstOrNull;
        if (me != null && me.isHost) {
          hostCheck = true;
        }
      } catch (_) {}

      setState(() {
        _isLoading = false;
        _prejoinMeeting = prejoin;
        _isHost = hostCheck;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _resolveError = 'Could not load meeting details: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  void _onSignInTapped() {
    context.go('/welcome');
  }

  void _onBackToMeetings() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/meetings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final s = context.vorynSpacing;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
              const SizedBox(height: 18),
              Text(
                'Checking meeting room...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_requiresLogin) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
            onPressed: _onBackToMeetings,
          ),
          title: const Text('VoRyn Meeting'),
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(s.screen),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_outline_rounded, color: colors.accent, size: 40),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sign In Required',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You received an invitation to join meeting code ${_normalizedCode ?? widget.rawCode}. Please sign in to verify your identity and view the room.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    VorynButton.primary(
                      label: 'Sign In to Continue',
                      onPressed: _onSignInTapped,
                    ),
                    const SizedBox(height: 12),
                    VorynButton.secondary(
                      label: 'Cancel',
                      onPressed: _onBackToMeetings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_parseError != null || _resolveError != null) {
      final errorMsg = _parseError ?? _resolveError!;
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
            onPressed: _onBackToMeetings,
          ),
          title: const Text('VoRyn Meeting'),
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(s.screen),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.danger.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.link_off_rounded, color: colors.danger, size: 40),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Meeting Unavailable',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      errorMsg,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_resolveError != null) ...[
                      VorynButton.secondary(
                        label: 'Try Again',
                        onPressed: _processLink,
                      ),
                      const SizedBox(height: 12),
                    ],
                    VorynButton.primary(
                      label: 'Back to Meetings',
                      onPressed: _onBackToMeetings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 4. Render the real, read-only PreJoinScreen
    return PreJoinScreen(
      meeting: _prejoinMeeting!,
      isHost: _isHost,
    );
  }
}

