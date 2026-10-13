import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../v2/v2_shared.dart';
import 'models/meeting_models.dart';
import 'services/voryn_meeting_service.dart';
import 'services/voryn_meeting_link_service.dart';
import 'meeting_room_screen.dart';
import 'widgets/meeting_invite_sheet.dart';

// =============================================================================
// MEETINGS TAB ROOT SCREEN
// =============================================================================

class MeetingsScreen extends StatefulWidget {
  const MeetingsScreen({super.key});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  late Future<List<VorynMeetingSummary>> _meetingsFuture;
  StreamSubscription<String>? _invitationSub;
  final Set<String> _selectedMeetingIds = {};
  bool _isDeleting = false;

  bool get _isSelectionMode => _selectedMeetingIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
    _invitationSub = VorynMeetingLinkService.onMeetingInvitationReceived.listen((_) {
      if (mounted) {
        _loadMeetings();
      }
    });
  }

  @override
  void dispose() {
    _invitationSub?.cancel();
    super.dispose();
  }

  void _loadMeetings() {
    setState(() {
      _selectedMeetingIds.clear();
      _meetingsFuture = VorynMeetingService.instance.listMyMeetings();
    });
  }

  void _toggleSelectMeeting(String id) {
    setState(() {
      if (_selectedMeetingIds.contains(id)) {
        _selectedMeetingIds.remove(id);
      } else {
        _selectedMeetingIds.add(id);
      }
    });
  }

  void _toggleSelectAllPastMeetings(List<VorynMeetingSummary> pastMeetings) {
    setState(() {
      if (_selectedMeetingIds.length == pastMeetings.length) {
        _selectedMeetingIds.clear();
      } else {
        _selectedMeetingIds.addAll(pastMeetings.map((m) => m.id));
      }
    });
  }

  Future<void> _confirmDeleteSelectedMeetings() async {
    final count = _selectedMeetingIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'meeting' : 'meetings'}?'),
        content: Text(
          'Remove $count selected ${count == 1 ? 'meeting' : 'meetings'} from your history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      final ids = _selectedMeetingIds.toList();
      try {
        await Future.wait(
          ids.map((id) => VorynMeetingService.instance.deletePastMeeting(id)),
        );
        if (mounted) {
          _selectedMeetingIds.clear();
          _loadMeetings();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed $count ${count == 1 ? 'meeting' : 'meetings'} from history.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.vorynSpacing;
    final colors = context.vorynColors;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                _loadMeetings();
                await _meetingsFuture;
              },
              color: colors.accent,
              backgroundColor: colors.surface,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  s.screen,
                  s.md,
                  s.screen,
                  _isSelectionMode ? 96 : s.screen,
                ),
                children: [
                  const VorynGlobalHeader(title: 'Meetings'),
                  SizedBox(height: s.xl),
                  Text(
                    'Meet together,\nwithout the friction.',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(height: 1.08),
                  ),
                  SizedBox(height: s.sm),
                  Text(
                    'Start a room for your team or join one in seconds.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: s.lg),
                  _MeetingActionPanel(
                    onNewMeeting: () async {
                      final created = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => const NewMeetingScreen()),
                      );
                      if (created == true) _loadMeetings();
                    },
                    onJoinMeeting: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JoinMeetingScreen()),
                    ),
                  ),
                  SizedBox(height: s.xl),
                  FutureBuilder<List<VorynMeetingSummary>>(
                    future: _meetingsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const _MeetingsLoadingSkeleton();
                      }

                      if (snapshot.hasError) {
                        return _MeetingsErrorView(
                          error: snapshot.error.toString(),
                          onRetry: _loadMeetings,
                        );
                      }

                      final meetings = snapshot.data ?? [];
                      if (meetings.isEmpty) {
                        return const _MeetingsEmptyView();
                      }

                      final readyOrActive = meetings.where((m) => m.isReady || m.isActive).toList();
                      final pastMeetings = meetings.where((m) => m.isEnded).toList();
                      final allPastSelected = pastMeetings.isNotEmpty &&
                          _selectedMeetingIds.length == pastMeetings.length;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (readyOrActive.isNotEmpty) ...[
                            Text(
                              'Upcoming & Active',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            SizedBox(height: s.sm),
                            ...readyOrActive.map(
                              (m) => Padding(
                                padding: EdgeInsets.only(bottom: s.sm),
                                child: _MeetingCard(
                                  meeting: m,
                                  onTap: () => _openMeetingDetails(m),
                                ),
                              ),
                            ),
                            SizedBox(height: s.lg),
                          ],
                          if (pastMeetings.isNotEmpty) ...[
                            if (_isSelectionMode)
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    tooltip: 'Cancel selection',
                                    onPressed: () => setState(() => _selectedMeetingIds.clear()),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_selectedMeetingIds.length} selected',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _toggleSelectAllPastMeetings(pastMeetings),
                                    icon: Icon(
                                      allPastSelected
                                          ? Icons.deselect_rounded
                                          : Icons.select_all_rounded,
                                      size: 18,
                                    ),
                                    label: Text(allPastSelected ? 'Deselect all' : 'Select all'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: colors.accent,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'Recent meetings',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            SizedBox(height: s.sm),
                            ...pastMeetings.map(
                              (m) => Padding(
                                padding: EdgeInsets.only(bottom: s.sm),
                                child: _MeetingCard(
                                  meeting: m,
                                  isSelectionMode: _isSelectionMode,
                                  isSelected: _selectedMeetingIds.contains(m.id),
                                  onTap: _isSelectionMode
                                      ? () => _toggleSelectMeeting(m.id)
                                      : () => _openMeetingDetails(m),
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    _toggleSelectMeeting(m.id);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom Floating Pip of Delete
            if (_isSelectionMode)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  color: colors.surface,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.border.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_selectedMeetingIds.length} selected',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _selectedMeetingIds.clear()),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _isDeleting ? null : _confirmDeleteSelectedMeetings,
                          icon: _isDeleting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_outline_rounded, size: 18),
                          label: Text('Delete (${_selectedMeetingIds.length})'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openMeetingDetails(VorynMeetingSummary meeting) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingDetailsScreen(
          meeting: meeting,
          meetingId: meeting.id,
        ),
      ),
    ).then((_) => _loadMeetings());
  }
}

// =============================================================================
// ACTION PANEL WIDGET
// =============================================================================

class _MeetingActionPanel extends StatelessWidget {
  const _MeetingActionPanel({
    required this.onNewMeeting,
    required this.onJoinMeeting,
  });

  final VoidCallback onNewMeeting;
  final VoidCallback onJoinMeeting;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(context.vorynRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MeetingAction(
              icon: Icons.add_rounded,
              label: 'New meeting',
              detail: 'Create a room',
              primary: true,
              onTap: onNewMeeting,
            ),
          ),
          Container(width: 1, height: 86, color: colors.border),
          Expanded(
            child: _MeetingAction(
              icon: Icons.keyboard_arrow_right_rounded,
              label: 'Join',
              detail: 'Use a code',
              onTap: onJoinMeeting,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingAction extends StatelessWidget {
  const _MeetingAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.vorynRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: primary ? colors.accent : colors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(icon, size: 21, color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 3),
                  Text(detail, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MEETING LIST ITEM CARD
// =============================================================================

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({
    required this.meeting,
    required this.onTap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
  });

  final VorynMeetingSummary meeting;
  final VoidCallback onTap;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final isUpcoming = meeting.isReady || meeting.isActive;

    Color badgeColor;
    String badgeText;
    if (meeting.isActive) {
      badgeColor = colors.accent;
      badgeText = 'Active';
    } else if (meeting.isReady) {
      badgeColor = colors.success;
      badgeText = 'Ready';
    } else if (meeting.status == 'cancelled') {
      badgeColor = colors.danger;
      badgeText = 'Cancelled';
    } else {
      badgeColor = colors.textMuted;
      badgeText = 'Ended';
    }

    return VorynCard(
      onPressed: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          if (isSelectionMode) ...[
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? colors.accent : colors.iconMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: isUpcoming ? colors.accentSoft : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(context.vorynRadii.md),
            ),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                isUpcoming ? Icons.videocam_rounded : Icons.history_rounded,
                color: isUpcoming ? colors.accent : colors.iconMuted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meeting.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: meeting.isHost
                            ? colors.accentSoft
                            : meeting.isInvited
                                ? colors.warning.withValues(alpha: 0.15)
                                : colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        meeting.isHost
                            ? 'Hosted'
                            : meeting.isInvited
                                ? 'Invited'
                                : 'Joined',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: meeting.isHost
                                  ? colors.accent
                                  : meeting.isInvited
                                      ? colors.warning
                                      : colors.textMuted,
                              fontSize: 10,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meeting.formattedDate,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${meeting.historicalAttendeeCount} attendees${meeting.formattedDuration != null ? ' · ${meeting.formattedDuration}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                badgeText,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: badgeColor),
              ),
              const SizedBox(height: 8),
              Icon(Icons.chevron_right_rounded, color: colors.iconMuted),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LOADING & EMPTY STATES
// =============================================================================

class _MeetingsLoadingSkeleton extends StatelessWidget {
  const _MeetingsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 76,
          decoration: BoxDecoration(
            color: colors.surfaceRaised.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(context.vorynRadii.md),
            border: Border.all(color: colors.border),
          ),
        ),
      ),
    );
  }
}

class _MeetingsEmptyView extends StatelessWidget {
  const _MeetingsEmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.groups_2_outlined, size: 48, color: colors.iconMuted),
            const SizedBox(height: 16),
            Text(
              'No meetings yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Start a room for your team or join with a code.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingsErrorView extends StatelessWidget {
  const _MeetingsErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: colors.danger),
          const SizedBox(height: 12),
          Text(
            'Unable to load meetings',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          VorynButton.secondary(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

// =============================================================================
// CREATE MEETING SCREEN
// =============================================================================

class NewMeetingScreen extends StatefulWidget {
  const NewMeetingScreen({super.key});

  @override
  State<NewMeetingScreen> createState() => _NewMeetingScreenState();
}

class _NewMeetingScreenState extends State<NewMeetingScreen> {
  final _titleController = TextEditingController(text: 'Team Meeting');
  String _access = 'link'; // 'link' | 'invited'
  String? _error;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_isCreating) return;
    final title = _titleController.text.trim();
    if (title.isEmpty || title.length > 60) {
      setState(() => _error = 'Please enter a meeting title (1-60 characters)');
      return;
    }

    setState(() {
      _error = null;
      _isCreating = true;
    });

    try {
      final created = await VorynMeetingService.instance.createMeeting(
        title: title,
        access: _access,
      );

      if (created.id.isEmpty || created.joinCode.isEmpty) {
        throw StateError('Server did not return a valid meeting ID or code.');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingCreatedScreen(meeting: created),
        ),
      );
    } catch (e) {
      if (e is PostgrestException) {
        debugPrint(
          '[MEETINGS] create_voryn_meeting PostgrestException: code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
        );
      } else {
        debugPrint('[MEETINGS] create_voryn_meeting error: $e');
      }

      if (mounted) {
        String userMessage = 'Failed to create meeting. Please try again.';
        if (e is PostgrestException && e.message.isNotEmpty) {
          userMessage = 'Failed to create meeting: ${e.message}';
        } else if (e is ArgumentError) {
          userMessage = 'Failed to create meeting: ${e.message}';
        } else {
          final clean = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
          if (clean.isNotEmpty && clean.length < 100) {
            userMessage = 'Failed to create meeting: $clean';
          }
        }

        setState(() {
          _error = userMessage;
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.vorynSpacing;
    final colors = context.vorynColors;

    return _Page(
      title: 'New meeting',
      child: ListView(
        padding: EdgeInsets.all(s.screen),
        children: [
          Text(
            'Create a Voryn meeting',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Set up your meeting before sharing the code with participants.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          VorynTextInput(
            label: 'Meeting title',
            controller: _titleController,
            hintText: 'Enter meeting title',
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 18),
          VorynSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Who can join', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _access == 'link' ? Icons.link_rounded : Icons.lock_outline_rounded,
                    color: colors.accent,
                  ),
                  title: Text(_access == 'link' ? 'Anyone with the link' : 'Only invited attendees'),
                  subtitle: Text(
                    _access == 'link'
                        ? 'Participants can join using the code'
                        : 'Only users specifically invited can join',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.arrow_drop_down_rounded),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.link_rounded),
                            title: const Text('Anyone with the link'),
                            subtitle: const Text('Fast open joining for your team'),
                            trailing: _access == 'link' ? const Icon(Icons.check_rounded) : null,
                            onTap: () {
                              setState(() => _access = 'link');
                              Navigator.pop(context);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.lock_outline_rounded),
                            title: const Text('Only invited attendees'),
                            subtitle: const Text('Restricted to authorized invitees'),
                            trailing: _access == 'invited' ? const Icon(Icons.check_rounded) : null,
                            onTap: () {
                              setState(() => _access = 'invited');
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          VorynButton.primary(
            label: _isCreating ? 'Creating...' : 'Create meeting',
            onPressed: _isCreating ? () {} : _create,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MEETING CREATED SUCCESS SCREEN
// =============================================================================

class MeetingCreatedScreen extends StatelessWidget {
  const MeetingCreatedScreen({super.key, required this.meeting});

  final VorynCreatedMeeting meeting;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final s = context.vorynSpacing;

    return _Page(
      title: 'Meeting ready',
      child: ListView(
        padding: EdgeInsets.all(s.screen),
        children: [
          const SizedBox(height: 30),
          Icon(
            Icons.check_circle_outline_rounded,
            color: colors.success,
            size: 64,
          ),
          const SizedBox(height: 18),
          Text(
            'Meeting created',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            meeting.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 28),
          VorynSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meeting Join Code', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                SelectableText(
                  meeting.joinCode,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        letterSpacing: 2.0,
                        color: colors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.surfaceRaised,
                        foregroundColor: colors.textPrimary,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: meeting.joinCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Meeting code copied to clipboard')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy Code'),
                    ),
                    if (VorynMeetingLinkService.isPublicDomainConfigured)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.surfaceRaised,
                          foregroundColor: colors.textPrimary,
                        ),
                        onPressed: () {
                          final link = VorynMeetingLinkService.buildMeetingLink(meeting.joinCode);
                          if (link != null) {
                            Clipboard.setData(ClipboardData(text: link));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Meeting link copied to clipboard')),
                            );
                          }
                        },
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Copy Link'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          VorynButton.primary(
            label: 'Start & Join Now',
            onPressed: () async {
              // Pre-join as host
              final prejoin = await VorynMeetingService.instance.resolveMeetingForPrejoin(meeting.joinCode);
              if (prejoin != null && context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreJoinScreen(meeting: prejoin, isHost: true),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          VorynButton.secondary(
            label: 'Back to Meetings',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// JOIN MEETING BY CODE SCREEN
// =============================================================================

class JoinMeetingScreen extends StatefulWidget {
  const JoinMeetingScreen({super.key});

  @override
  State<JoinMeetingScreen> createState() => _JoinMeetingScreenState();
}

class _JoinMeetingScreenState extends State<JoinMeetingScreen> {
  final _codeController = TextEditingController();
  String? _error;
  bool _isSearching = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final raw = _codeController.text.trim();
    final normalized = normalizeMeetingJoinCode(raw);
    if (normalized == null) {
      setState(() => _error = 'Enter a valid meeting code (format: xxx-xxx-xxx)');
      return;
    }

    setState(() {
      _error = null;
      _isSearching = true;
    });

    try {
      final prejoin = await VorynMeetingService.instance.resolveMeetingForPrejoin(normalized);
      if (!mounted) return;

      if (prejoin == null) {
        setState(() {
          _error = 'Meeting not found or already ended. Please check the code.';
          _isSearching = false;
        });
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreJoinScreen(meeting: prejoin),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error resolving meeting: ${e.toString().replaceAll('Exception: ', '')}';
          _isSearching = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.vorynSpacing;

    return _Page(
      title: 'Join meeting',
      child: ListView(
        padding: EdgeInsets.all(s.screen),
        children: [
          const SizedBox(height: 20),
          Text(
            'Join a Voryn meeting',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 9-character code shared by the host.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 26),
          VorynTextInput(
            label: 'Meeting code',
            controller: _codeController,
            hintText: 'abc-123-xyz',
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 22),
          VorynButton.primary(
            label: _isSearching ? 'Finding room...' : 'Continue',
            onPressed: _isSearching ? () {} : _continue,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PRE-JOIN SCREEN
// =============================================================================

class PreJoinScreen extends StatefulWidget {
  const PreJoinScreen({
    super.key,
    required this.meeting,
    this.isHost = false,
  });

  final VorynPrejoinMeeting meeting;
  final bool isHost;

  @override
  State<PreJoinScreen> createState() => _PreJoinScreenState();
}

class _PreJoinScreenState extends State<PreJoinScreen> {
  bool _mic = true;
  bool _camera = false;
  bool _isJoining = false;
  String? _joinError;

  Future<void> _toggleCamera(bool value) async {
    if (value) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission denied')),
          );
        }
        return;
      }
    }
    setState(() => _camera = value);
  }

  Future<void> _join() async {
    setState(() {
      _isJoining = true;
      _joinError = null;
    });

    try {
      // If host and meeting is ready, start meeting first
      if (widget.isHost && widget.meeting.status == 'ready') {
        await VorynMeetingService.instance.startMeeting(widget.meeting.meetingId);
      }

      // Explicitly join via join_voryn_meeting and negotiate LiveKit token
      final joined = await VorynMeetingService.instance.joinMeeting(
        widget.meeting.joinCode,
        initialMic: _mic,
        initialCamera: _camera,
      );

      if (!mounted) return;

      // Pop prejoin from the tab shell so leaving the meeting returns cleanly to Meetings tab
      final nav = Navigator.of(context);
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (nav != rootNav) {
        nav.pop();
      }

      // Launch MeetingRoomScreen on the root navigator outside the shell
      rootNav.push(
        MaterialPageRoute(
          settings: RouteSettings(name: '/meeting-room/${joined.meetingId}'),
          builder: (_) => MeetingRoomScreen(
            joinedMeeting: joined,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _joinError = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
          _isJoining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final s = context.vorynSpacing;

    return _Page(
      title: widget.meeting.title,
      child: ListView(
        padding: EdgeInsets.all(s.screen),
        children: [
          Text(
            widget.meeting.title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person_pin_circle_outlined, size: 16, color: colors.iconMuted),
              const SizedBox(width: 4),
              Text(
                'Host: ${widget.meeting.hostName ?? "Host"}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 12),
              Icon(Icons.groups_outlined, size: 16, color: colors.iconMuted),
              const SizedBox(width: 4),
              Text(
                '${widget.meeting.activeParticipantCount} / ${widget.meeting.capacity} active',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Camera preview surface
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: VorynSurface(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_camera) ...[
                    Icon(
                      Icons.videocam_rounded,
                      color: colors.accent,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Camera is ready',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Media will publish upon entering the room',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ] else ...[
                    const VorynAvatar(
                      initials: 'VM',
                      size: VorynAvatarSize.large,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Camera is off',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Control(
                icon: _mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                label: _mic ? 'Mic on' : 'Mic muted',
                active: _mic,
                onTap: () => setState(() => _mic = !_mic),
              ),
              _Control(
                icon: _camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                label: _camera ? 'Camera on' : 'Camera off',
                active: _camera,
                onTap: () => _toggleCamera(!_camera),
              ),
            ],
          ),
          if (_joinError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(context.vorynRadii.md),
                border: Border.all(color: colors.danger),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: colors.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _joinError!,
                      style: TextStyle(color: colors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          VorynButton.primary(
            label: _isJoining
                ? 'Joining room...'
                : (widget.isHost ? 'Start & Join' : 'Join Meeting'),
            onPressed: _isJoining ? () {} : _join,
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Column(
      children: [
        IconButton.filled(
          onPressed: onTap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: active ? colors.accent : colors.surfaceRaised,
            minimumSize: const Size(54, 54),
          ),
          tooltip: label,
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// =============================================================================
// MEETING DETAILS SCREEN
// =============================================================================

class MeetingDetailsScreen extends StatefulWidget {
  const MeetingDetailsScreen({
    super.key,
    required this.meeting,
    required this.meetingId,
    this.meetingService,
  });

  final VorynMeetingSummary meeting;
  final String meetingId;
  final VorynMeetingService? meetingService;

  @override
  State<MeetingDetailsScreen> createState() => _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends State<MeetingDetailsScreen> {
  late final VorynMeetingService _service =
      widget.meetingService ?? VorynMeetingService.instance;

  List<VorynMeetingParticipant> _participants = const [];
  bool _loadingParticipants = true;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    try {
      final list = await _service.getMeetingParticipants(widget.meetingId);
      if (mounted) {
        setState(() {
          _participants = list;
          _loadingParticipants = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingParticipants = false);
    }
  }

  void _openInviteSheet() {
    MeetingInviteSheet.show(
      context,
      meetingId: widget.meetingId,
      meetingTitle: widget.meeting.title,
      meetingService: _service,
      onInvitationsSent: _loadParticipants,
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).toList();
    return parts.isNotEmpty ? parts.map((p) => p[0].toUpperCase()).join() : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final s = context.vorynSpacing;
    final radii = context.vorynRadii;
    final meeting = widget.meeting;

    return _Page(
      title: 'Meeting Details',
      child: ListView(
        padding: EdgeInsets.all(s.screen),
        children: [
          VorynSurface(
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(context.vorynRadii.md),
                  ),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(Icons.videocam_rounded, color: colors.accent, size: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meeting.title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        meeting.formattedDate,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (meeting.isInvited) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(radii.md),
                border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_unread_rounded, color: colors.warning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are invited to this meeting',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap Join Pre-Join Room below to verify your device and join.',
                          style: TextStyle(color: colors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          _Info(label: 'Status', value: meeting.status.toUpperCase()),
          _Info(
            label: 'My Role',
            value: meeting.isHost
                ? 'Host'
                : meeting.isInvited
                    ? 'Invited Guest'
                    : 'Participant',
          ),
          _Info(
            label: 'Attendees',
            value: '${meeting.historicalAttendeeCount} historical attendee(s)',
          ),
          if (meeting.formattedDuration != null)
            _Info(label: 'Duration', value: meeting.formattedDuration!),
          _Info(label: 'Join Code', value: meeting.joinCode),
          const SizedBox(height: 20),

          // Action Buttons
          if (meeting.isReady || meeting.isActive) ...[
            VorynButton.primary(
              label: 'Join Pre-Join Room',
              onPressed: () async {
                final prejoin = await _service.resolveMeetingForPrejoin(meeting.joinCode);
                if (prejoin != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PreJoinScreen(
                        meeting: prejoin,
                        isHost: meeting.isHost,
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            VorynButton.secondary(
              label: 'Invite Contacts',
              onPressed: _openInviteSheet,
            ),
            const SizedBox(height: 12),
          ],

          VorynButton.secondary(
            label: 'Copy Join Code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: meeting.joinCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join code copied to clipboard')),
              );
            },
          ),
          if (VorynMeetingLinkService.isPublicDomainConfigured) ...[
            const SizedBox(height: 12),
            VorynButton.secondary(
              label: 'Copy Meeting Link',
              onPressed: () {
                final link = VorynMeetingLinkService.buildMeetingLink(meeting.joinCode);
                if (link != null) {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Meeting link copied to clipboard')),
                  );
                }
              },
            ),
          ],

          // Participants & Invitations Section
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Participants',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if ((meeting.isReady || meeting.isActive) && _participants.isNotEmpty)
                TextButton.icon(
                  onPressed: _openInviteSheet,
                  icon: Icon(Icons.person_add_rounded, size: 16, color: colors.accent),
                  label: Text('Invite', style: TextStyle(color: colors.accent, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_loadingParticipants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                  ),
                ),
              ),
            )
          else if (_participants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No participant records loaded yet.',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else
            ..._participants.map((p) {
              final isInMeeting = p.joinedAt != null && p.leftAt == null;
              final isInvited = p.invitedAt != null && p.joinedAt == null;

              String badgeLabel;
              Color badgeColor;
              Color badgeBg;
              if (p.isHost) {
                badgeLabel = 'Host';
                badgeColor = colors.accent;
                badgeBg = colors.accentSoft;
              } else if (isInMeeting) {
                badgeLabel = 'In meeting';
                badgeColor = colors.accent;
                badgeBg = colors.accent.withValues(alpha: 0.15);
              } else if (isInvited) {
                badgeLabel = 'Invited';
                badgeColor = colors.textMuted;
                badgeBg = colors.surfaceRaised;
              } else {
                badgeLabel = 'Left';
                badgeColor = colors.textMuted;
                badgeBg = colors.surfaceRaised;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(radii.md),
                ),
                child: Row(
                  children: [
                    VorynAvatar(
                      initials: _getInitials(p.displayName),
                      size: VorynAvatarSize.small,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          if (p.isHost)
                            Text(
                              'Meeting Organizer',
                              style: TextStyle(color: colors.textMuted, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

// =============================================================================
// ACTIVE MEETING ROOM PLACEHOLDER SCREEN (MEET-3A Integration Placeholder)
// =============================================================================

class MeetingRoomPlaceholderScreen extends StatelessWidget {
  const MeetingRoomPlaceholderScreen({
    super.key,
    required this.joinedMeeting,
    required this.meetingId,
  });

  final VorynJoinedMeeting joinedMeeting;
  final String meetingId;

  @override
  Widget build(BuildContext context) {
    return MeetingRoomScreen(joinedMeeting: joinedMeeting);
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: child,
      );
}
