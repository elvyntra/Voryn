import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/voryn_theme.dart';
import '../../core/theme/voryn_theme_controller.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';
import '../v2/v2_shared.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileScreen> {
  String name = 'Vikash Mishra';
  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: EdgeInsets.all(spacing.screen),
        children: [
          const Center(
            child: VorynAvatar(initials: 'VM', size: VorynAvatarSize.xlarge),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const Center(child: Text('@vikash')),
          const Center(child: Text('Online')),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: VorynButton.secondary(
                  label: 'Edit profile',
                  onPressed: () async {
                    final result = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(name: name),
                      ),
                    );
                    if (result != null) setState(() => name = result);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VorynButton.primary(
                  label: 'Share',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ShareProfileScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const VorynSurface(
            child: Column(
              children: [
                _Info(label: 'Voryn ID', value: '@vikash'),
                _Info(label: 'Phone', value: '+91 98765 43210 · Verified'),
                _Info(label: 'Email', value: 'vikash@example.com · Verified'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          VorynCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Do Not Disturb'),
              subtitle: const Text(
                'Block new call interruptions while staying online.',
              ),
              value: mockDoNotDisturb,
              onChanged: (value) => setState(() => mockDoNotDisturb = value),
            ),
          ),
          for (final item in [
            'Privacy',
            'Notifications',
            'Calling',
            'Appearance',
            'Blocked users',
            'Devices',
            'Help',
          ])
            VorynCard(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsDetailScreen(title: item),
                ),
              ),
              child: _Row(icon: _settingIcon(item), title: item),
            ),
          VorynCard(
            onPressed: () => _logout(context),
            child: _Row(
              icon: Icons.logout_rounded,
              title: 'Log out',
              destructive: true,
            ),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Log out of Voryn?'),
      content: const Text("You'll need to sign in again to continue."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            '/welcome',
            (_) => false,
          ),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.name});
  final String name;
  @override
  State<EditProfileScreen> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfileScreen> {
  late final controller = TextEditingController(text: widget.name);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit profile')),
    body: ListView(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      children: [
        Center(
          child: GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile photo options are mock-only.'),
              ),
            ),
            child: const VorynAvatar(
              initials: 'VM',
              size: VorynAvatarSize.xlarge,
            ),
          ),
        ),
        const SizedBox(height: 22),
        VorynTextInput(label: 'Full name', controller: controller),
        const SizedBox(height: 16),
        const VorynTextInput(label: 'Voryn ID', hintText: '@vikash_new'),
        const SizedBox(height: 16),
        const ListTile(
          title: Text('Phone'),
          subtitle: Text('+91 98765 43210 · Verified'),
        ),
        const ListTile(
          title: Text('Email'),
          subtitle: Text('vikash@example.com · Verified'),
        ),
        const SizedBox(height: 18),
        VorynButton.primary(
          label: 'Save changes',
          onPressed: () => Navigator.pop(context, controller.text.trim()),
        ),
      ],
    ),
  );
}

class ShareProfileScreen extends StatelessWidget {
  const ShareProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share profile')),
    body: ListView(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      children: [
        const SizedBox(height: 30),
        const Center(
          child: Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 210),
        ),
        const SizedBox(height: 18),
        const Center(child: Text('Vikash Mishra')),
        const Center(child: Text('@vikash')),
        const SizedBox(height: 24),
        VorynButton.primary(
          label: 'Copy ID',
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: '@vikash'));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Voryn ID copied')));
          },
        ),
        const SizedBox(height: 10),
        VorynButton.secondary(
          label: 'Share profile',
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Profile sharing will be connected during integration.',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class SettingsDetailScreen extends StatefulWidget {
  const SettingsDetailScreen({super.key, required this.title});
  final String title;
  @override
  State<SettingsDetailScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsDetailScreen> {
  final values = <String, bool>{};
  @override
  Widget build(BuildContext context) {
    if (widget.title == 'Appearance') return const AppearanceScreen();
    final rows = switch (widget.title) {
      'Privacy' => [
        'Find me by Voryn ID',
        'Find me by phone number',
        'Find me by email',
        'Show when I\'m online',
        'Who can call me',
      ],
      'Notifications' => [
        'Incoming calls',
        'Missed calls',
        'Meeting invitations',
        'Vibration',
        'Sound',
      ],
      'Calling' => [
        'Microphone when joining',
        'Camera when joining',
        'Audio output',
        'Use less data for calls',
      ],
      'Appearance' => ['System', 'Light', 'Dark'],
      _ => [
        'Calling help',
        'Meeting help',
        'Privacy & safety',
        'Report a problem',
        'About Voryn',
      ],
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: EdgeInsets.all(context.vorynSpacing.screen),
        children: [
          for (final row in rows)
            VorynCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row),
                subtitle: Text(
                  widget.title == 'Help'
                      ? 'Open local information'
                      : 'Local mock preference',
                ),
                value: values[row] ?? true,
                onChanged: (v) => setState(() => values[row] = v),
              ),
            ),
        ],
      ),
    );
  }
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = VorynThemeController.current;
    final selected = controller?.mode ?? ThemeMode.system;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: EdgeInsets.all(context.vorynSpacing.screen),
        children: [
          Text(
            'Choose how Voryn looks',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          for (final option in [
            ThemeMode.system,
            ThemeMode.light,
            ThemeMode.dark,
          ])
            VorynCard(
              onPressed: controller == null
                  ? null
                  : () => controller.setMode(option),
              child: Row(
                children: [
                  Icon(
                    selected == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected == option
                        ? context.vorynColors.accent
                        : context.vorynColors.iconMuted,
                  ),
                  const SizedBox(width: 12),
                  Text(_themeLabel(option)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsState();
}

class _PermissionsState extends State<PermissionsScreen> {
  final statuses = <String, String>{
    'Microphone': 'Not requested',
    'Camera': 'Not requested',
    'Notifications': 'Not requested',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Permissions')),
    body: ListView(
      padding: EdgeInsets.all(context.vorynSpacing.screen),
      children: [
        Text(
          'Allow Voryn to make calls',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text('Voryn needs a few permissions for calling features.'),
        for (final entry in statuses.entries)
          VorynCard(
            onPressed: () => setState(
              () => statuses[entry.key] = statuses[entry.key] == 'Not requested'
                  ? 'Allowed'
                  : 'Denied',
            ),
            child: _Row(
              icon: Icons.check_circle_outline,
              title: entry.key,
              detail: '${entry.value} · mock only',
            ),
          ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(value),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.detail,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String? detail;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (detail != null)
              Text(detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const Icon(Icons.chevron_right_rounded),
    ],
  );
}

IconData _settingIcon(String value) => switch (value) {
  'Privacy' => Icons.lock_outline_rounded,
  'Notifications' => Icons.notifications_none_rounded,
  'Calling' => Icons.phone_outlined,
  'Appearance' => Icons.palette_outlined,
  'Blocked users' => Icons.block_outlined,
  'Devices' => Icons.devices_outlined,
  _ => Icons.help_outline_rounded,
};
