import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import 'mock_voryn_state.dart';
import 'user_interaction_screens.dart';
import 'voryn_discovery_service.dart';
import '../v2/v2_shared.dart';

enum _SearchMode { vorynId, phone }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  _SearchMode _mode = _SearchMode.vorynId;
  bool _searched = false;
  bool _searching = false;
  VorynMockUser? _remoteResult;
  String? _searchError;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<VorynMockUser> get _results {
    final query = _search.text.trim();
    if (query.isEmpty) {
      return mockVorynUsers.take(3).toList();
    }
    final lower = query.toLowerCase();
    final numeric = query.replaceAll(RegExp(r'[^0-9]'), '');
    int rank(VorynMockUser user) {
      final custom = user.customName?.toLowerCase() ?? '';
      final name = user.name.toLowerCase();
      final id = user.id.toLowerCase();
      final phone = user.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (_mode == _SearchMode.vorynId && query.startsWith('@')) {
        return id == lower
            ? 0
            : id.startsWith(lower)
            ? 1
            : -1;
      }
      if (_mode == _SearchMode.phone &&
          numeric.length >= 3 &&
          numeric == phone.substring(phone.length - numeric.length)) {
        return 0;
      }
      if (_mode == _SearchMode.phone) return -1;
      if (custom == lower) {
        return 0;
      }
      if (custom.startsWith(lower)) {
        return 1;
      }
      if (id == lower) {
        return 2;
      }
      if (id.startsWith(lower)) {
        return 3;
      }
      if (name == lower || name.startsWith(lower)) {
        return 4;
      }
      if (phone.contains(numeric) && numeric.isNotEmpty) {
        return 5;
      }
      if (custom.contains(lower) ||
          name.contains(lower) ||
          id.contains(lower)) {
        return 7;
      }
      return -1;
    }

    final matching = mockVorynUsers.where((u) => rank(u) >= 0).toList();
    matching.sort((a, b) => rank(a).compareTo(rank(b)));
    return matching;
  }

  List<VorynMockUser> get _recentUsers {
    final ids = <String>{};
    return mockRecentCalls
        .map(
          (call) => mockVorynUsers
              .where((user) => user.id == call.userId)
              .firstOrNull,
        )
        .whereType<VorynMockUser>()
        .where((user) => ids.add(user.id))
        .take(4)
        .toList();
  }

  Future<void> _searchNow() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final query = _search.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searched = false;
        _remoteResult = null;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searched = true;
      _searching = true;
      _remoteResult = null;
      _searchError = null;
    });
    try {
      final result = _mode == _SearchMode.vorynId
          ? await const VorynDiscoveryService().findByVorynId(query)
          : await const VorynDiscoveryService().findByPhone(query);
      if (!mounted) return;
      setState(() {
        _remoteResult = result == null
            ? null
            : VorynMockUser.fromDiscovery(result);
        if (_remoteResult != null &&
            !mockVorynUsers.any((user) => user.id == _remoteResult!.id)) {
          mockVorynUsers.add(_remoteResult!);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = 'Could not search Voryn right now.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final results = _search.text.trim().isEmpty
        ? _recentUsers
        : _searched
        ? (_remoteResult == null ? const [] : [_remoteResult!])
        : _results;
    return SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          spacing.screen,
          0,
          spacing.screen,
          spacing.screen,
        ),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.screen,
              spacing.md,
              spacing.screen,
              spacing.sm,
            ),
            child: const VorynGlobalHeader(
              title: 'Connect',
              subtitle: 'Find and call people on Voryn.',
            ),
          ),
          SizedBox(height: spacing.lg),
          Text(
            'Who do you want to connect with?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Find someone using their Voryn ID or phone number.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: spacing.lg),
          SegmentedButton<_SearchMode>(
            segments: const [
              ButtonSegment(
                value: _SearchMode.vorynId,
                label: Text('Voryn ID'),
                icon: Icon(Icons.alternate_email),
              ),
              ButtonSegment(
                value: _SearchMode.phone,
                label: Text('Phone'),
                icon: Icon(Icons.phone_outlined),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              _searchFocus.unfocus();
              setState(() {
                _mode = selection.first;
                _search.clear();
                _searched = false;
                _remoteResult = null;
                _searchError = null;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _searchFocus.requestFocus();
              });
            },
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.screen,
              vertical: spacing.sm,
            ),
            child: TextField(
              key: ValueKey(_mode),
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (_) => setState(() {
                _searched = false;
                _remoteResult = null;
                _searchError = null;
              }),
              onSubmitted: (_) => _searchNow(),
              keyboardType: _mode == _SearchMode.phone
                  ? TextInputType.phone
                  : TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: _mode == _SearchMode.phone
                    ? 'Enter phone number'
                    : 'Enter Voryn ID',
                prefixIcon: Icon(
                  _mode == _SearchMode.phone
                      ? Icons.add_call
                      : Icons.alternate_email,
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          VorynButton.primary(
            label: 'Search',
            leadingIcon: Icons.search_rounded,
            isLoading: _searching,
            onPressed: _searching ? null : _searchNow,
          ),
          SizedBox(height: spacing.xl),
          if (_searched && _searchError != null)
            VorynSurface(
              child: Text(_searchError!, textAlign: TextAlign.center),
            )
          else if (_searched &&
              _search.text.trim().isNotEmpty &&
              results.isEmpty)
            VorynSurface(
              child: Column(
                children: [
                  const Icon(Icons.person_search_outlined, size: 34),
                  SizedBox(height: spacing.sm),
                  Text(
                    'User not found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    _mode == _SearchMode.phone
                        ? 'No Voryn user matches this phone number.'
                        : 'No Voryn user matches this Voryn ID.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _search.text.trim().isEmpty
                      ? 'Recently connected'
                      : 'Matches',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: spacing.sm),
                ...results.map((user) => _UserRow(user: user)),
                SizedBox(height: spacing.md),
                Text(
                  'Favorites',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: spacing.sm),
                Row(
                  children: mockVorynUsers
                      .where((u) => u.isFavorite)
                      .take(4)
                      .map((user) => Expanded(child: _Favorite(user: user)))
                      .toList(),
                ),
              ],
            ),
          /*
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(spacing.screen),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_outlined,
                            color: colors.textMuted,
                            size: 36,
                          ),
                          SizedBox(height: spacing.md),
                          Text(
                            'No Voryn user found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: spacing.xs),
                          Text(
                            'Check the Voryn ID, phone number, email, or name.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.screen,
                      vertical: spacing.sm,
                    ),
                    children: [
                      Text(
                        _search.text.trim().isEmpty ? 'Suggestions' : 'Results',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      SizedBox(height: spacing.sm),
                      ...results.map((user) => _UserRow(user: user)),
                    ],
                  ),
          ),*/
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});
  final VorynMockUser user;
  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: VorynCard(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserPreviewScreen(user: user)),
        ),
        padding: EdgeInsets.all(spacing.sm),
        child: Row(
          children: [
            VorynAvatar(
              initials: user.initials,
              size: VorynAvatarSize.medium,
              presenceStatus: user.presence,
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: spacing.xxs),
                  Text(
                    '${user.name} · ${user.id}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: spacing.xxs),
                  VorynPresenceIndicator(
                    status: user.presence,
                    label: user.presence.name,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.iconMuted),
          ],
        ),
      ),
    );
  }
}

class _Favorite extends StatelessWidget {
  const _Favorite({required this.user});
  final VorynMockUser user;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UserPreviewScreen(user: user))),
    child: Column(
      children: [
        VorynAvatar(initials: user.initials, size: VorynAvatarSize.medium),
        const SizedBox(height: 6),
        Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
