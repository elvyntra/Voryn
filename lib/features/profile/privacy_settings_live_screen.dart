import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_card.dart';
import 'voryn_profile_service.dart';

class PrivacySettingsLiveScreen extends StatefulWidget {
  const PrivacySettingsLiveScreen({super.key});

  @override
  State<PrivacySettingsLiveScreen> createState() =>
      _PrivacySettingsLiveScreenState();
}

class _PrivacySettingsLiveScreenState extends State<PrivacySettingsLiveScreen> {
  final _profileService = const VorynProfileService();
  late Future<VorynPrivacySettings?> _future = _load();
  VorynPrivacySettings? _settings;

  Future<VorynPrivacySettings?> _load() async {
    final s = await _profileService.loadPrivacySettings();
    if (mounted && s != null) {
      setState(() => _settings = s);
    }
    return s;
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _update({
    bool? dndEnabled,
    String? whoCanCall,
    bool? showOnlineStatus,
  }) async {
    if (_settings == null) return;
    final previous = _settings!;
    final updated = previous.copyWith(
      dndEnabled: dndEnabled,
      whoCanCall: whoCanCall,
      showOnlineStatus: showOnlineStatus,
    );
    setState(() => _settings = updated);

    final success = await _profileService.updatePrivacySettings(
      dndEnabled: dndEnabled,
      whoCanCall: whoCanCall,
      showOnlineStatus: showOnlineStatus,
    );

    if (!success && mounted) {
      setState(() => _settings = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update privacy settings. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: FutureBuilder<VorynPrivacySettings?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _settings == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_settings == null) {
            return Center(
              child: VorynSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load privacy settings.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final spacing = context.vorynSpacing;
          final settings = _settings!;

          return ListView(
            padding: EdgeInsets.all(spacing.screen),
            children: [
              Text('Calls', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: spacing.sm),
              VorynCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Do Not Disturb'),
                  subtitle: const Text(
                    'Reject incoming calls while staying online.',
                  ),
                  value: settings.dndEnabled,
                  onChanged: (val) => _update(dndEnabled: val),
                ),
              ),
              SizedBox(height: spacing.lg),
              Text(
                'Who can call me',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              SizedBox(height: spacing.sm),
              VorynSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _WhoCanCallTile(
                      title: 'Everyone',
                      subtitle: 'Anyone on Voryn can call you',
                      value: 'everyone',
                      groupValue: settings.whoCanCall,
                      onChanged: (val) => _update(whoCanCall: val),
                    ),
                    const Divider(height: 1),
                    _WhoCanCallTile(
                      title: 'Saved contacts',
                      subtitle: 'Only people in your contacts can call you',
                      value: 'saved_contacts',
                      groupValue: settings.whoCanCall,
                      onChanged: (val) => _update(whoCanCall: val),
                    ),
                    const Divider(height: 1),
                    _WhoCanCallTile(
                      title: 'Nobody',
                      subtitle: 'Block all incoming direct calls',
                      value: 'nobody',
                      groupValue: settings.whoCanCall,
                      onChanged: (val) => _update(whoCanCall: val),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.lg),
              Text('Presence', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: spacing.sm),
              VorynCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show online status'),
                  subtitle: const Text(
                    'Allow others to see when you are active on Voryn.',
                  ),
                  value: settings.showOnlineStatus,
                  onChanged: (val) => _update(showOnlineStatus: val),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WhoCanCallTile extends StatelessWidget {
  const _WhoCanCallTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? context.vorynColors.accent
                  : context.vorynColors.iconMuted,
            ),
          ],
        ),
      ),
    );
  }
}
