import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../contacts/voryn_contact_service.dart';
import '../v2/v2_shared.dart';
import 'user_interaction_screens.dart';
import 'voryn_discovery_service.dart';
import 'voryn_live_user.dart';

enum _LiveSearchMode { vorynId, phone }

class ConnectLiveScreen extends StatefulWidget {
  const ConnectLiveScreen({super.key});

  @override
  State<ConnectLiveScreen> createState() => _ConnectLiveScreenState();
}

class _ConnectLiveScreenState extends State<ConnectLiveScreen> {
  final _controller = TextEditingController();
  _LiveSearchMode _mode = _LiveSearchMode.vorynId;
  bool _loadingContacts = true;
  bool _searching = false;
  String? _error;
  VorynDiscoveryResult? _result;
  List<VorynStoredContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _loadingContacts = true);
    try {
      final contacts = await const VorynContactService().loadContacts();
      if (mounted) setState(() => _contacts = contacts);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your contacts.');
    } finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Future<void> _search() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });
    try {
      final result = _mode == _LiveSearchMode.vorynId
          ? await const VorynDiscoveryService().findByVorynId(value)
          : await const VorynDiscoveryService().findByPhone(value);
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search Voryn right now.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final favorites = _contacts.where((contact) => contact.favorite).toList();
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(spacing.screen),
        children: [
          const VorynGlobalHeader(
            title: 'Connect',
            subtitle: 'Find people on Voryn.',
          ),
          SizedBox(height: spacing.xl),
          Text(
            'Who do you want to connect with?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: spacing.sm),
          SegmentedButton<_LiveSearchMode>(
            segments: const [
              ButtonSegment(
                value: _LiveSearchMode.vorynId,
                label: Text('Voryn ID'),
              ),
              ButtonSegment(value: _LiveSearchMode.phone, label: Text('Phone')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() {
              _mode = value.first;
              _controller.clear();
              _result = null;
            }),
          ),
          SizedBox(height: spacing.md),
          TextField(
            controller: _controller,
            keyboardType: _mode == _LiveSearchMode.phone
                ? TextInputType.phone
                : TextInputType.text,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: _mode == _LiveSearchMode.phone
                  ? 'Enter phone number'
                  : 'Enter Voryn ID',
              prefixIcon: Icon(
                _mode == _LiveSearchMode.phone
                    ? Icons.phone_outlined
                    : Icons.alternate_email,
              ),
            ),
          ),
          SizedBox(height: spacing.sm),
          VorynButton.primary(
            label: 'Search',
            leadingIcon: Icons.search_rounded,
            isLoading: _searching,
            onPressed: _searching ? null : _search,
          ),
          SizedBox(height: spacing.xl),
          if (_error != null)
            _StateCard(message: _error!, onRetry: _loadContacts),
          if (_result != null) ...[
            Text('Match', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: spacing.sm),
            _LiveUserRow(user: liveUserFromDiscovery(_result!)),
            SizedBox(height: spacing.xl),
          ] else if (!_searching &&
              _controller.text.trim().isNotEmpty &&
              _error == null)
            const _StateCard(message: 'No Voryn user matches that search.'),
          Text('Favorites', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: spacing.sm),
          if (_loadingContacts)
            const Center(child: CircularProgressIndicator())
          else if (favorites.isEmpty)
            const _StateCard(
              message: 'Your favorite contacts will appear here.',
            )
          else
            ...favorites.map(
              (contact) => _LiveUserRow(user: liveUserFromContact(contact)),
            ),
          SizedBox(height: spacing.xl),
          Text('Saved contacts', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: spacing.sm),
          if (_loadingContacts)
            const SizedBox.shrink()
          else if (_contacts.isEmpty)
            const _StateCard(message: 'Save a Voryn contact to find them here.')
          else
            ..._contacts.map(
              (contact) => _LiveUserRow(user: liveUserFromContact(contact)),
            ),
        ],
      ),
    );
  }
}

class _LiveUserRow extends StatelessWidget {
  const _LiveUserRow({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: VorynCard(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserPreviewScreen(user: user)),
      ),
      child: Row(
        children: [
          VorynAvatar(initials: user.initials, size: VorynAvatarSize.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(user.id, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => VorynSurface(
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
