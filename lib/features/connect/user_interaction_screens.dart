import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import '../../core/backend/voryn_backend.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import '../../shared/widgets/voryn_text_input.dart';
import 'mock_voryn_state.dart';
import '../calling/voryn_call_service.dart';
import '../contacts/voryn_contact_service.dart';
import '../messages/voryn_call_message_service.dart';

class UserPreviewScreen extends StatefulWidget {
  const UserPreviewScreen({super.key, required this.user});

  final VorynMockUser user;

  @override
  State<UserPreviewScreen> createState() => _UserPreviewScreenState();
}

class _UserPreviewScreenState extends State<UserPreviewScreen> {
  VorynMockUser get user => widget.user;
  bool get saved => user.isSaved;
  late bool _blocked = mockBlockedIds.contains(user.id);

  void _feedback(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleBlock(bool block) async {
    setState(() => _blocked = block);
    setMockBlocked(user, block);
    final candidate = user.backendUid ?? user.id;
    await const VorynContactService().setBlocked(candidate, block);
    _feedback(block ? 'User blocked' : 'User unblocked');
  }

  Future<void> _startDirectCall({required bool video}) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text('Calling ${user.displayName}…'),
        duration: const Duration(seconds: 2),
      ),
    );

    final candidate = user.backendUid ?? user.id;
    final req = await const VorynCallService().start(
      vorynId: candidate,
      video: video,
    );

    if (!mounted) return;
    if (req.isSuccess && req.id != null) {
      final loc = video
          ? '/active-video-call/${req.id}'
          : '/active-audio-call/${req.id}';
      context.push(loc, extra: {'user': user});
    } else {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(req.error ?? 'Could not start call. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;

    return Scaffold(
      appBar: AppBar(title: const Text('User Preview')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(spacing.screen),
          children: [
            Center(
              child: VorynAvatar(
                initials: user.initials,
                size: VorynAvatarSize.xlarge,
                presenceStatus: user.presence,
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              user.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.xxs),
            Text(
              '${user.name} · ${user.id}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.xs),
            Center(
              child: VorynPresenceIndicator(
                status: user.presence,
                label: user.presence.name,
              ),
            ),
            SizedBox(height: spacing.xl),
            if (_blocked) ...[
              VorynSurface(
                child: Row(
                  children: [
                    Icon(Icons.block, color: colors.danger),
                    SizedBox(width: spacing.sm),
                    Text(
                      'Blocked',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: colors.danger),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.md),
              VorynButton.secondary(
                label: 'Unblock',
                onPressed: () => _toggleBlock(false),
              ),
            ] else ...[
              Row(
                children: [
                  _CallOption(
                    icon: Icons.phone_outlined,
                    label: 'Audio call',
                    onTap: () => _startDirectCall(video: false),
                  ),
                  SizedBox(width: spacing.xs),
                  _CallOption(
                    icon: Icons.videocam_outlined,
                    label: 'Video call',
                    onTap: () => _startDirectCall(video: true),
                  ),
                  SizedBox(width: spacing.xs),
                  _CallOption(
                    icon: Icons.chat_bubble_outline,
                    label: 'Message',
                    onTap: () => _showMessageSheet(context),
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              if (saved)
                Center(
                  child: Text(
                    'Contact saved ✓',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: colors.success),
                  ),
                )
              else
                VorynButton.secondary(
                  label: 'Save contact',
                  leadingIcon: Icons.person_add_alt_1_outlined,
                  onPressed: () => _showSaveSheet(context),
                ),
            ],
            SizedBox(height: spacing.xl),
            _InfoSection(user: user),
            if (saved) ...[
              SizedBox(height: spacing.xl),
              Text('Contact', style: Theme.of(context).textTheme.labelMedium),
              SizedBox(height: spacing.sm),
              VorynCard(
                onPressed: () => _showEditSheet(context),
                child: _ActionRow(
                  icon: Icons.edit_outlined,
                  label: 'Edit contact',
                  value: user.displayName,
                ),
              ),
              VorynCard(
                onPressed: () {
                  setState(() => setMockFavorite(user, !user.isFavorite));
                  _feedback(
                    user.isFavorite
                        ? 'Added to favorites'
                        : 'Removed from favorites',
                  );
                },
                child: _ActionRow(
                  icon: user.isFavorite ? Icons.star : Icons.star_border,
                  label: user.isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  value: user.isFavorite ? 'Favorite' : null,
                ),
              ),
              VorynCard(
                onPressed: () => _confirmRemoveContact(context),
                child: _ActionRow(
                  icon: Icons.person_remove_alt_1_outlined,
                  label: 'Remove contact',
                  destructive: true,
                ),
              ),
            ],
            SizedBox(height: spacing.xl),
            TextButton.icon(
              onPressed: () => _confirmBlock(context),
              icon: Icon(Icons.block, color: colors.danger),
              label: Text('Block user', style: TextStyle(color: colors.danger)),
            ),
            TextButton.icon(
              onPressed: () => _showReportSheet(context),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report user'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => QuickMessageSheet(user: user),
  );

  void _showSaveSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SaveContactSheet(
      user: user,
      onSaved: (name) {
        setState(() => saveMockContact(user, name));
      },
    ),
  );

  void _showEditSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SaveContactSheet(
      user: user,
      title: 'Edit contact',
      label: 'Saved as',
      initialName: user.displayName,
      onSaved: (name) {
        setState(() => saveMockContact(user, name));
      },
    ),
  );

  void _confirmRemoveContact(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove ${user.displayName} from contacts?'),
      content: const Text(
        'This removes your private saved contact. Their Voryn account is not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            removeMockContact(user);
            Navigator.pop(dialogContext);
            setState(() {});
            _feedback('Contact removed');
          },
          child: Text(
            'Remove',
            style: TextStyle(color: context.vorynColors.danger),
          ),
        ),
      ],
    ),
  );

  void _confirmBlock(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Block this user?'),
      content: Text(
        '${user.displayName} won\'t be able to contact you on Voryn while blocked.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            _toggleBlock(true);
          },
          child: Text(
            'Block',
            style: TextStyle(color: context.vorynColors.danger),
          ),
        ),
      ],
    ),
  );

  void _showReportSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReportUserSheet(user: user),
  );
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.user});

  final VorynMockUser user;

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return VorynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoLine(label: 'Voryn ID', value: user.id),
          SizedBox(height: spacing.md),
          _InfoLine(label: 'Phone', value: user.phone),
          SizedBox(height: spacing.md),
          if (user.isSaved) ...[
            SizedBox(height: spacing.md),
            _InfoLine(label: 'Saved as', value: user.displayName),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    this.value,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final color = destructive ? colors.danger : colors.textPrimary;

    return Row(
      children: [
        Icon(icon, color: destructive ? colors.danger : colors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: color),
          ),
        ),
        if (value != null)
          Flexible(
            child: Text(
              value!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        Icon(Icons.chevron_right_rounded, color: colors.iconMuted),
      ],
    );
  }
}

class _CallOption extends StatelessWidget {
  const _CallOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: VorynCard(
      onPressed: onTap,
      child: Column(
        children: [
          Icon(icon, color: context.vorynColors.accent),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    ),
  );
}

class QuickMessageSheet extends StatefulWidget {
  const QuickMessageSheet({super.key, required this.user});

  final VorynMockUser user;

  @override
  State<QuickMessageSheet> createState() => _QuickMessageSheetState();
}

class _QuickMessageSheetState extends State<QuickMessageSheet> {
  final _message = TextEditingController();
  bool _remind = false;
  bool _sending = false;
  String? _preset;

  static const _presets = [
    "Call me when you're free.",
    'Are you free for a call?',
    "I'll call you later.",
    'Can we talk for a minute?',
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final canSend = _preset != null || _message.text.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.screen,
          8,
          spacing.screen,
          MediaQuery.viewInsetsOf(context).bottom + spacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Message ${widget.user.displayName}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              '${widget.user.name} · ${widget.user.id}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.lg),
            for (final preset in _presets)
              VorynCard(
                onPressed: () {
                  setState(() {
                    _preset = preset;
                    _message.clear();
                  });
                },
                enabled: true,
                child: Row(
                  children: [
                    Icon(
                      _preset == preset
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _preset == preset
                          ? context.vorynColors.accent
                          : context.vorynColors.iconMuted,
                    ),
                    SizedBox(width: spacing.sm),
                    Expanded(child: Text(preset)),
                  ],
                ),
              ),
            SizedBox(height: spacing.sm),
            TextField(
              controller: _message,
              maxLength: 120,
              onChanged: (_) => setState(() => _preset = null),
              decoration: const InputDecoration(labelText: 'Write a message'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remind,
              onChanged: (value) => setState(() => _remind = value),
              title: const Text('Remind them to call me'),
            ),
            VorynButton.primary(
              label: 'Send',
              isLoading: _sending,
              onPressed: canSend && !_sending ? _send : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _preset ?? _message.text;
    setState(() => _sending = true);
    final result = await const VorynCallMessageService().send(
      recipientVorynId: widget.user.id,
      body: text,
      remindToCall: _remind,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _remind
              ? 'Message sent. They were asked to call you back.'
              : 'Message sent',
        ),
      ),
    );
  }
}

class SaveContactSheet extends StatefulWidget {
  const SaveContactSheet({
    super.key,
    required this.user,
    required this.onSaved,
    this.title = 'Save contact',
    this.label = 'Save as',
    this.initialName,
  });

  final VorynMockUser user;
  final ValueChanged<String> onSaved;
  final String title;
  final String label;
  final String? initialName;

  @override
  State<SaveContactSheet> createState() => _SaveContactSheetState();
}

class _SaveContactSheetState extends State<SaveContactSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName ?? widget.user.name,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.screen,
          8,
          spacing.screen,
          MediaQuery.viewInsetsOf(context).bottom + spacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.sm),
            Text(
              widget.user.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(widget.user.id, style: Theme.of(context).textTheme.bodyMedium),
            SizedBox(height: spacing.lg),
            VorynTextInput(
              label: widget.label,
              controller: _name,
              errorText: _error,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'This name is private and only visible to you.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: VorynButton.primary(
                    label: 'Save',
                    onPressed: () {
                      final value = _name.text.trim();
                      if (value.isEmpty) {
                        setState(() => _error = 'Enter a contact name');
                        return;
                      }
                      widget.onSaved(value);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReportUserSheet extends StatefulWidget {
  const ReportUserSheet({super.key, required this.user});

  final VorynMockUser user;

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  String? _selectedCode;
  final _details = TextEditingController();
  bool _submitting = false;

  static const _reasons = [
    ('Spam', 'spam'),
    ('Harassment', 'harassment'),
    ('Impersonation', 'impersonation'),
    ('Suspicious activity', 'suspicious_activity'),
    ('Other', 'other'),
  ];

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCode == null || _submitting) return;
    setState(() => _submitting = true);
    final client = VorynBackend.client;
    final candidate = widget.user.backendUid ?? widget.user.id;
    try {
      if (client != null && client.auth.currentUser != null) {
        await client.rpc(
          'submit_user_report',
          params: {
            'candidate': candidate,
            'report_reason': _selectedCode,
            'report_details': _details.text.trim().isEmpty
                ? null
                : _details.text.trim(),
          },
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report submitted. Thank you for keeping Voryn safe.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit report. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.screen,
          8,
          spacing.screen,
          MediaQuery.viewInsetsOf(context).bottom + spacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Report user',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Tell us what happened.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.md),
            for (final entry in _reasons)
              VorynCard(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _selectedCode = entry.$2),
                child: Row(
                  children: [
                    Icon(
                      _selectedCode == entry.$2
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _selectedCode == entry.$2
                          ? context.vorynColors.accent
                          : context.vorynColors.iconMuted,
                    ),
                    SizedBox(width: spacing.sm),
                    Expanded(child: Text(entry.$1)),
                  ],
                ),
              ),
            if (_selectedCode == 'other')
              TextField(
                controller: _details,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: 'Additional details',
                ),
              ),
            SizedBox(height: spacing.sm),
            VorynButton.primary(
              label: 'Submit report',
              isLoading: _submitting,
              onPressed: (_selectedCode == null || _submitting)
                  ? null
                  : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
