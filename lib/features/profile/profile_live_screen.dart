import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../auth/voryn_auth_service.dart';
import 'voryn_profile.dart';
import 'voryn_profile_service.dart';

class ProfileLiveScreen extends StatefulWidget {
  const ProfileLiveScreen({super.key});

  @override
  State<ProfileLiveScreen> createState() => _ProfileLiveScreenState();
}

class _ProfileLiveScreenState extends State<ProfileLiveScreen> {
  late Future<VorynProfile?> _profile = _load();

  Future<VorynProfile?> _load() => const VorynProfileService().currentProfile();
  void _reload() => setState(() => _profile = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: FutureBuilder<VorynProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snapshot.data;
        if (snapshot.hasError || profile == null) {
          return _ProfileState(
            message:
                'Could not load your profile. Sign in again and try once more.',
            action: _reload,
          );
        }
        return _ProfileBody(profile: profile, onChanged: _reload);
      },
    ),
  );
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile, required this.onChanged});

  final VorynProfile profile;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final name = profile.fullName.trim().isEmpty
        ? 'Voryn user'
        : profile.fullName;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return ListView(
      padding: EdgeInsets.all(spacing.screen),
      children: [
        Center(
          child: VorynAvatar(
            initials: initials.isEmpty ? '?' : initials,
            size: VorynAvatarSize.xlarge,
            imageProvider: profile.avatarUrl?.isNotEmpty == true
                ? NetworkImage(profile.avatarUrl!)
                : null,
          ),
        ),
        SizedBox(height: spacing.md),
        Text(
          name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        SizedBox(height: spacing.xxs),
        Text('@${profile.vorynId ?? 'not-set'}', textAlign: TextAlign.center),
        SizedBox(height: spacing.lg),
        VorynButton.primary(
          label: 'Edit profile',
          leadingIcon: Icons.edit_outlined,
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditLiveProfileScreen(profile: profile),
              ),
            );
            onChanged();
          },
        ),
        SizedBox(height: spacing.lg),
        VorynSurface(
          child: Column(
            children: [
              _Info(
                label: 'Voryn ID',
                value: profile.vorynId == null
                    ? 'Not set'
                    : '@${profile.vorynId}',
              ),
              _Info(
                label: 'Phone',
                value: profile.phone?.isNotEmpty == true
                    ? profile.phone!
                    : 'Not added',
              ),
              _Info(label: 'Email', value: profile.email ?? 'Not available'),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        VorynCard(
          onPressed: () async {
            if (profile.vorynId == null) return;
            await Clipboard.setData(ClipboardData(text: '@${profile.vorynId}'));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Voryn ID copied')));
            }
          },
          child: const _SettingRow(
            icon: Icons.content_copy_rounded,
            label: 'Copy Voryn ID',
          ),
        ),
        VorynCard(
          onPressed: () async {
            await const VorynAuthService().signOut();
            if (context.mounted) context.go('/welcome');
          },
          child: _SettingRow(
            icon: Icons.logout_rounded,
            label: 'Log out',
            destructive: true,
          ),
        ),
      ],
    );
  }
}

class EditLiveProfileScreen extends StatefulWidget {
  const EditLiveProfileScreen({super.key, required this.profile});
  final VorynProfile profile;

  @override
  State<EditLiveProfileScreen> createState() => _EditLiveProfileScreenState();
}

class _EditLiveProfileScreenState extends State<EditLiveProfileScreen> {
  late final _name = TextEditingController(text: widget.profile.fullName);
  Uint8List? _avatar;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => _avatar = bytes);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await const VorynProfileService().upsertProfile(fullName: name);
      if (_avatar != null) {
        await const VorynProfileService().uploadAvatar(_avatar!);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your profile.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit profile')),
    body: ListView(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      children: [
        Center(
          child: GestureDetector(
            onTap: _saving ? null : _pickAvatar,
            child: Stack(
              children: [
                VorynAvatar(
                  initials: _name.text.isEmpty
                      ? '?'
                      : _name.text[0].toUpperCase(),
                  size: VorynAvatarSize.xlarge,
                  imageProvider: _avatar == null ? null : MemoryImage(_avatar!),
                ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: Icon(Icons.add_a_photo_outlined),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        VorynTextInput(label: 'Full name', controller: _name),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Voryn ID'),
          subtitle: Text('@${widget.profile.vorynId ?? 'Not set'}'),
        ),
        ListTile(
          title: const Text('Phone'),
          subtitle: Text(
            widget.profile.phone?.isNotEmpty == true
                ? widget.profile.phone!
                : 'Not added',
          ),
        ),
        ListTile(
          title: const Text('Email'),
          subtitle: Text(widget.profile.email ?? 'Not available'),
        ),
        const SizedBox(height: 18),
        VorynButton.primary(
          label: 'Save changes',
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    ),
  );
}

class _ProfileState extends StatelessWidget {
  const _ProfileState({required this.message, required this.action});
  final String message;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Center(
    child: VorynSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: action, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(value),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final bool destructive;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        icon,
        color: destructive
            ? context.vorynColors.danger
            : context.vorynColors.accent,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: destructive ? context.vorynColors.danger : null,
          ),
        ),
      ),
      const Icon(Icons.chevron_right_rounded),
    ],
  );
}
