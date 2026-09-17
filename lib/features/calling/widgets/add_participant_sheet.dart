import 'package:flutter/material.dart';

import '../../../core/theme/voryn_theme.dart';
import '../../../shared/widgets/voryn_avatar.dart';
import '../../connect/mock_voryn_state.dart';
import '../../contacts/voryn_contact_service.dart';
import '../voryn_call_history_service.dart';
import '../voryn_call_service.dart';

class AddParticipantCandidate {
  final String id;
  final String name;
  final String vorynId;
  final String? phone;
  final bool isBlocked;

  const AddParticipantCandidate({
    required this.id,
    required this.name,
    required this.vorynId,
    this.phone,
    this.isBlocked = false,
  });
}

class AddParticipantSheet extends StatefulWidget {
  const AddParticipantSheet({
    super.key,
    required this.callId,
    this.onParticipantInvited,
  });

  final String callId;
  final ValueChanged<String>? onParticipantInvited;

  static Future<void> show(
    BuildContext context, {
    required String callId,
    ValueChanged<String>? onParticipantInvited,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16191E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddParticipantSheet(
        callId: callId,
        onParticipantInvited: onParticipantInvited,
      ),
    );
  }

  @override
  State<AddParticipantSheet> createState() => _AddParticipantSheetState();
}

class _AddParticipantSheetState extends State<AddParticipantSheet> {
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _errorMessage;

  List<AddParticipantCandidate> _contacts = const [];
  List<AddParticipantCandidate> _recents = const [];
  final Set<String> _invitingIds = {};
  final Set<String> _invitedIds = {};

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() => _loading = true);
    final contactCandidates = <AddParticipantCandidate>[];
    final recentCandidates = <AddParticipantCandidate>[];

    try {
      final storedContacts = await const VorynContactService().loadContacts();
      for (final c in storedContacts) {
        if (!c.blocked) {
          contactCandidates.add(
            AddParticipantCandidate(
              id: c.uid,
              name: c.displayName,
              vorynId: c.vorynId.startsWith('@') ? c.vorynId : '@${c.vorynId}',
              phone: c.phone,
              isBlocked: c.blocked,
            ),
          );
        }
      }
    } catch (_) {}

    try {
      final history = await const VorynCallHistoryService().load();
      final seen = <String>{};
      for (final h in history) {
        if (h.vorynId.isNotEmpty && !seen.contains(h.vorynId)) {
          seen.add(h.vorynId);
          recentCandidates.add(
            AddParticipantCandidate(
              id: h.otherUid,
              name: h.displayName,
              vorynId: h.vorynId.startsWith('@') ? h.vorynId : '@${h.vorynId}',
            ),
          );
        }
      }
    } catch (_) {}

    // Fallback: seed with mock users if lists are empty (e.g. mock test environment)
    if (contactCandidates.isEmpty && recentCandidates.isEmpty) {
      for (final u in mockVorynUsers) {
        contactCandidates.add(
          AddParticipantCandidate(
            id: u.id,
            name: u.name,
            vorynId: u.id,
            phone: u.phone,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _contacts = contactCandidates;
        _recents = recentCandidates;
        _loading = false;
      });
    }
  }

  List<AddParticipantCandidate> get _filteredList {
    final query = _searchController.text.trim().toLowerCase();
    final combined = <String, AddParticipantCandidate>{};
    for (final c in _contacts) {
      combined[c.vorynId.toLowerCase()] = c;
    }
    for (final r in _recents) {
      combined.putIfAbsent(r.vorynId.toLowerCase(), () => r);
    }

    final all = combined.values.toList();
    if (query.isEmpty) return all;

    return all
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              c.vorynId.toLowerCase().contains(query) ||
              (c.phone ?? '').contains(query),
        )
        .toList();
  }

  Future<void> _invite(AddParticipantCandidate candidate) async {
    final cleanVorynId = candidate.vorynId.trim().replaceFirst('@', '');
    if (_invitingIds.contains(cleanVorynId) ||
        _invitedIds.contains(cleanVorynId)) {
      return;
    }

    setState(() {
      _invitingIds.add(cleanVorynId);
      _errorMessage = null;
    });

    final isCandidateIdUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(candidate.id);

    try {
      await const VorynCallService().addParticipant(
        callId: widget.callId,
        candidate: cleanVorynId,
        targetUserId: isCandidateIdUuid ? candidate.id : null,
      );

      if (mounted) {
        setState(() {
          _invitingIds.remove(cleanVorynId);
          _invitedIds.add(cleanVorynId);
        });
        widget.onParticipantInvited?.call(cleanVorynId);
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _invitingIds.remove(cleanVorynId);
          _errorMessage = message.contains('PGRST')
              ? "Couldn't invite this person. Try again."
              : message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final candidates = _filteredList;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 12,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
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
              const SizedBox(height: 16),

              // Title
              Row(
                children: [
                  const Icon(
                    Icons.group_add_rounded,
                    color: Color(0xFF22C55E),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add People to Call',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by name or @voryn_id',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: colors.iconMuted,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF20242B),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF22C55E)),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B1818),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Candidate List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF22C55E),
                        ),
                      )
                    : candidates.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'No contacts found'
                              : 'No matches found',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: candidates.length,
                        separatorBuilder: (context, index) => Divider(
                          color: colors.border.withValues(alpha: 0.4),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final cleanId = candidate.vorynId.trim().replaceFirst(
                            '@',
                            '',
                          );
                          final isInviting = _invitingIds.contains(cleanId);
                          final isInvited = _invitedIds.contains(cleanId);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            leading: VorynAvatar(
                              initials: candidate.name.isNotEmpty
                                  ? candidate.name[0].toUpperCase()
                                  : '?',
                              size: VorynAvatarSize.medium,
                            ),
                            title: Text(
                              candidate.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              candidate.vorynId,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            trailing: ElevatedButton(
                              onPressed: isInviting || isInvited
                                  ? null
                                  : () => _invite(candidate),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isInvited
                                    ? const Color(0xFF10281E)
                                    : const Color(0xFF22C55E),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: isInvited
                                    ? const Color(0xFF10281E)
                                    : colors.surfaceRaised,
                                disabledForegroundColor: isInvited
                                    ? const Color(0xFF22C55E)
                                    : colors.textMuted,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: isInviting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : isInvited
                                  ? const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                          color: Color(0xFF22C55E),
                                        ),
                                        SizedBox(width: 4),
                                        Text('Invited'),
                                      ],
                                    )
                                  : const Text(
                                      'Invite',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
