import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_presence.dart';
import 'mock_voryn_state.dart';
import 'user_interaction_screens.dart';
import '../v2/v2_shared.dart';

enum KeyboardMode { letters, symbols }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _search = TextEditingController();
  KeyboardMode _mode = KeyboardMode.letters;
  bool _shift = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _insert(String value) {
    final text = _search.text;
    if (value == ' ' && (text.isEmpty || text.endsWith(' '))) {
      return;
    }
    if (value == '@' && text.endsWith('@')) {
      return;
    }
    final inserted =
        _shift && value.length == 1 && RegExp('[a-z]').hasMatch(value)
        ? value.toUpperCase()
        : value;
    _search.value = TextEditingValue(
      text: text + inserted,
      selection: TextSelection.collapsed(offset: text.length + inserted.length),
    );
    if (_shift && RegExp('[a-zA-Z]').hasMatch(value)) {
      setState(() => _shift = false);
    }
    setState(() {});
  }

  void _delete() {
    if (_search.text.isEmpty) return;
    _search.value = TextEditingValue(
      text: _search.text.substring(0, _search.text.length - 1),
      selection: TextSelection.collapsed(offset: _search.text.length - 1),
    );
    setState(() {});
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
      if (query.startsWith('@')) {
        return id == lower
            ? 0
            : id.startsWith(lower)
            ? 1
            : -1;
      }
      if (numeric.length >= 3 &&
          numeric == phone.substring(phone.length - numeric.length)) {
        return 0;
      }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    final results = _results;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              subtitle: 'Find and call people on VoRyn.',
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.screen,
              vertical: spacing.sm,
            ),
            child: TextField(
              controller: _search,
              readOnly: true,
              showCursor: true,
              onTap: () {},
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Search name, Voryn ID or phone',
                prefixIcon: const Icon(Icons.search_rounded),
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
          ),
          VorynKeyboard(
            mode: _mode,
            shift: _shift,
            onModeChanged: (mode) => setState(() => _mode = mode),
            onShift: () => setState(() => _shift = !_shift),
            onKey: _insert,
            onDelete: _delete,
          ),
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

class VorynKeyboard extends StatelessWidget {
  const VorynKeyboard({
    super.key,
    required this.mode,
    required this.shift,
    required this.onModeChanged,
    required this.onShift,
    required this.onKey,
    required this.onDelete,
  });
  final KeyboardMode mode;
  final bool shift;
  final ValueChanged<KeyboardMode> onModeChanged;
  final VoidCallback onShift;
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    final rows = mode == KeyboardMode.letters
        ? <List<String>>[
            ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
            (shift ? 'QWERTYUIOP' : 'qwertyuiop').split(''),
            (shift ? 'ASDFGHJKL' : 'asdfghjkl').split(''),
            ['⇧', ...(shift ? 'ZXCVBNM' : 'zxcvbnm').split('')],
          ]
        : <List<String>>[
            ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
            ['@', '#', '₹', '&', '_', '-', '+', '(', ')', '/'],
            ['*', '"', "'", ':', ';', '!', '?', '.', ','],
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.xs,
          spacing.sm,
          spacing.xs,
          spacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final key in row)
                      Flexible(
                        child: VorynKeyboardKey(
                          label: key,
                          onPressed: key == '⇧' ? onShift : () => onKey(key),
                        ),
                      ),
                  ],
                ),
              ),
            _bottomRow(context),
          ],
        ),
      ),
    );
  }

  Widget _bottomRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 13,
          child: VorynKeyboardKey(
            label: mode == KeyboardMode.letters ? '?123' : 'ABC',
            onPressed: () => onModeChanged(
              mode == KeyboardMode.letters
                  ? KeyboardMode.symbols
                  : KeyboardMode.letters,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          flex: 10,
          child: VorynKeyboardKey(label: '@', onPressed: () => onKey('@')),
        ),
        const SizedBox(width: 5),
        Expanded(
          flex: 32,
          child: VorynKeyboardKey(label: 'SPACE', onPressed: () => onKey(' ')),
        ),
        const SizedBox(width: 5),
        Expanded(
          flex: 10,
          child: VorynKeyboardKey(label: '.', onPressed: () => onKey('.')),
        ),
        const SizedBox(width: 5),
        Expanded(
          flex: 13,
          child: VorynKeyboardKey(
            label: '⌫',
            semanticLabel: 'Delete',
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class VorynKeyboardKey extends StatefulWidget {
  const VorynKeyboardKey({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });
  final String label;
  final String? semanticLabel;
  final VoidCallback onPressed;
  @override
  State<VorynKeyboardKey> createState() => _VorynKeyboardKeyState();
}

class _VorynKeyboardKeyState extends State<VorynKeyboardKey> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed ? colors.surfacePressed : colors.surfaceRaised,
            borderRadius: BorderRadius.circular(context.vorynRadii.sm),
          ),
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: widget.label == 'SPACE' ? 12 : 16,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
