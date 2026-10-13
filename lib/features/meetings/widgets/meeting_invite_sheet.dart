import 'package:flutter/material.dart';

import '../../../core/theme/voryn_theme.dart';
import '../../../shared/widgets/voryn_avatar.dart';
import '../../../shared/widgets/voryn_button.dart';
import '../../contacts/voryn_contact_service.dart';
import '../models/meeting_models.dart';
import '../services/voryn_meeting_service.dart';

/// Modal sheet for browsing, searching, and inviting VoRyn contacts to a meeting.
class MeetingInviteSheet extends StatefulWidget {
  const MeetingInviteSheet({
    super.key,
    required this.meetingId,
    this.meetingTitle,
    this.meetingService,
    this.contactService = const VorynContactService(),
    this.onInvitationsSent,
  });

  final String meetingId;
  final String? meetingTitle;
  final VorynMeetingService? meetingService;
  final VorynContactService contactService;
  final VoidCallback? onInvitationsSent;

  static Future<void> show(
    BuildContext context, {
    required String meetingId,
    String? meetingTitle,
    VorynMeetingService? meetingService,
    VorynContactService contactService = const VorynContactService(),
    VoidCallback? onInvitationsSent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MeetingInviteSheet(
        meetingId: meetingId,
        meetingTitle: meetingTitle,
        meetingService: meetingService,
        contactService: contactService,
        onInvitationsSent: onInvitationsSent,
      ),
    );
  }

  @override
  State<MeetingInviteSheet> createState() => _MeetingInviteSheetState();
}

class _MeetingInviteSheetState extends State<MeetingInviteSheet> {
  final _searchController = TextEditingController();
  late final VorynMeetingService _meetingService =
      widget.meetingService ?? VorynMeetingService.instance;

  bool _loading = true;
  bool _sending = false;
  String? _errorMessage;
  String? _statusBanner;

  List<VorynStoredContact> _allContacts = const [];
  List<VorynMeetingParticipant> _existingParticipants = const [];
  final Set<String> _selectedUids = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _meetingService.getEligibleContacts(
          widget.meetingId,
          contactService: widget.contactService,
        ),
        _meetingService.getMeetingParticipants(widget.meetingId),
      ]);

      if (mounted) {
        setState(() {
          _allContacts = results[0] as List<VorynStoredContact>;
          _existingParticipants = results[1] as List<VorynMeetingParticipant>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Could not load contacts: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  Set<String> get _activeUids => _existingParticipants
      .where((p) => p.joinedAt != null && p.leftAt == null)
      .map((p) => p.userUid)
      .toSet();

  Set<String> get _invitedUids => _existingParticipants
      .where((p) => p.invitedAt != null && p.joinedAt == null)
      .map((p) => p.userUid)
      .toSet();

  List<VorynStoredContact> get _filteredContacts {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _allContacts;
    return _allContacts.where((c) {
      final name = c.displayName.toLowerCase();
      final id = c.vorynId.toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  void _toggleSelection(String uid) {
    if (_activeUids.contains(uid) || _invitedUids.contains(uid)) return;
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedUids.clear());
  }

  Future<void> _sendInvitations() async {
    if (_selectedUids.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _statusBanner = null;
      _errorMessage = null;
    });

    final targetList = _selectedUids.toList();
    final results = await _meetingService.inviteParticipants(
      widget.meetingId,
      targetList,
    );

    if (!mounted) return;

    final successful = results.where((r) => r.isSuccess).toList();
    final failed = results.where((r) => !r.isSuccess).toList();

    // Reload participants to refresh badges
    await _loadData();

    if (!mounted) return;

    setState(() {
      _sending = false;
      // Remove successful ones from selection
      for (final s in successful) {
        _selectedUids.remove(s.userUid);
      }

      if (failed.isEmpty) {
        _statusBanner = 'Invitations sent successfully!';
      } else if (successful.isNotEmpty) {
        _statusBanner = 'Sent ${successful.length} invitation(s). ${failed.length} failed.';
      } else {
        _errorMessage = 'Failed to send invitations: ${failed.first.errorMessage ?? 'Unknown error'}';
      }
    });

    if (successful.isNotEmpty) {
      widget.onInvitationsSent?.call();
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).toList();
    return parts.isNotEmpty ? parts.map((p) => p[0].toUpperCase()).join() : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final radii = context.vorynRadii;
    final s = context.vorynSpacing;
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: media.size.height * 0.85,
        maxWidth: 540,
      ),
      margin: EdgeInsets.only(
        top: media.padding.top + 20,
        bottom: media.viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radii.xl)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header row
            Padding(
              padding: EdgeInsets.symmetric(horizontal: s.screen),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite to Meeting',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.meetingTitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.meetingTitle!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.textMuted,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_selectedUids.isNotEmpty)
                    TextButton(
                      onPressed: _sending ? null : _clearSelection,
                      child: Text(
                        'Clear',
                        style: TextStyle(color: colors.accent),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.iconMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Search Bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: s.screen),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search contacts by name or @voryn_id',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: colors.iconMuted, size: 20),
                  filled: true,
                  fillColor: colors.surfaceRaised,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radii.md),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(radii.md),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Feedback banners
            if (_errorMessage != null)
              Container(
                margin: EdgeInsets.symmetric(horizontal: s.screen, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(radii.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: colors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: colors.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            if (_statusBanner != null)
              Container(
                margin: EdgeInsets.symmetric(horizontal: s.screen, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(radii.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: colors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusBanner!,
                        style: TextStyle(color: colors.success, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Contact list
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                      ),
                    )
                  : _filteredContacts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'No eligible contacts found'
                                  : 'No contacts matching "${_searchController.text}"',
                              style: TextStyle(color: colors.textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.symmetric(horizontal: s.screen, vertical: 8),
                          itemCount: _filteredContacts.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            thickness: 0.5,
                            color: colors.border.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) {
                            final contact = _filteredContacts[index];
                            final isInMeeting = _activeUids.contains(contact.uid);
                            final isInvited = _invitedUids.contains(contact.uid);
                            final isSelected = _selectedUids.contains(contact.uid);
                            final isActionDisabled = isInMeeting || isInvited;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: VorynAvatar(
                                initials: _getInitials(contact.displayName),
                                size: VorynAvatarSize.small,
                              ),
                              title: Text(
                                contact.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isActionDisabled ? colors.textMuted : colors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '@${contact.vorynId}',
                                style: TextStyle(color: colors.textMuted, fontSize: 12),
                              ),
                              trailing: isInMeeting
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colors.accent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'In meeting',
                                        style: TextStyle(
                                          color: colors.accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    )
                                  : isInvited
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: colors.surfaceRaised,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Invited',
                                            style: TextStyle(
                                              color: colors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        )
                                      : Checkbox(
                                          value: isSelected,
                                          activeColor: colors.accent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          onChanged: isActionDisabled
                                              ? null
                                              : (_) => _toggleSelection(contact.uid),
                                        ),
                              onTap: isActionDisabled
                                  ? null
                                  : () => _toggleSelection(contact.uid),
                            );
                          },
                        ),
            ),

            // Action button bar
            Padding(
              padding: EdgeInsets.all(s.screen),
              child: VorynButton.primary(
                label: _sending
                    ? 'Sending invitations...'
                    : _selectedUids.isEmpty
                        ? 'Select contacts to invite'
                        : 'Send ${_selectedUids.length} invitation${_selectedUids.length > 1 ? 's' : ''}',
                onPressed: _selectedUids.isEmpty || _sending ? null : _sendInvitations,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

