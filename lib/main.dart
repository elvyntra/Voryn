import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/voryn_theme.dart';
import 'features/auth/auth_screens.dart';
import 'features/connect/connect_screen.dart';
import 'features/contacts/contacts_screen.dart';
import 'features/recents/recents_screen.dart';
import 'features/meetings/meetings_screen.dart';
import 'features/onboarding/onboarding_screens.dart';
import 'shared/widgets/voryn_avatar.dart';
import 'shared/widgets/voryn_card.dart';
import 'shared/widgets/voryn_presence.dart';

void main() => runApp(const VorynApp());

class VorynApp extends StatelessWidget {
  const VorynApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'VoRyn',
      debugShowCheckedModeBanner: false,
      theme: VorynTheme.light,
      darkTheme: VorynTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: _buildRouter(),
    );
  }
}

GoRouter _buildRouter() {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final shellNavigatorConnectKey = GlobalKey<NavigatorState>(
    debugLabel: 'connect',
  );
  final shellNavigatorRecentsKey = GlobalKey<NavigatorState>(
    debugLabel: 'recents',
  );
  final shellNavigatorContactsKey = GlobalKey<NavigatorState>(
    debugLabel: 'contacts',
  );
  final shellNavigatorMeetingsKey = GlobalKey<NavigatorState>(
    debugLabel: 'meetings',
  );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/onboarding/verify-phone',
        builder: (context, state) => const VerifyPhoneScreen(),
      ),
      GoRoute(
        path: '/onboarding/voryn-id',
        builder: (context, state) => const CreateVorynIdScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return VorynShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: shellNavigatorConnectKey,
            routes: [
              GoRoute(
                path: '/connect',
                builder: (context, state) => const ConnectScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: shellNavigatorRecentsKey,
            routes: [
              GoRoute(
                path: '/recents',
                builder: (context, state) => const RecentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: shellNavigatorContactsKey,
            routes: [
              GoRoute(
                path: '/contacts',
                builder: (context, state) => const ContactsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: shellNavigatorMeetingsKey,
            routes: [
              GoRoute(
                path: '/meetings',
                builder: (context, state) => const MeetingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

enum VorynTab {
  connect(
    label: 'Connect',
    icon: VorynIcons.connect,
    headline: 'Connect',
    detail: 'Primary Connect tab placeholder',
  ),
  recents(
    label: 'Recents',
    icon: VorynIcons.recents,
    headline: 'Recents',
    detail: 'Recent activity placeholder',
  ),
  contacts(
    label: 'Contacts',
    icon: VorynIcons.contacts,
    headline: 'Contacts',
    detail: 'Contacts list placeholder',
  ),
  meetings(
    label: 'Meetings',
    icon: VorynIcons.meetings,
    headline: 'Meetings',
    detail: 'Meetings hub placeholder',
  );

  const VorynTab({
    required this.label,
    required this.icon,
    required this.headline,
    required this.detail,
  });

  final String label;
  final IconData icon;
  final String headline;
  final String detail;
}

class VorynShell extends StatelessWidget {
  const VorynShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return Scaffold(
      backgroundColor: colors.background,
      body: navigationShell,
      bottomNavigationBar: VorynBottomNavigation(
        currentIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

class VorynBottomNavigation extends StatelessWidget {
  const VorynBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundSoft,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (final (index, tab) in VorynTab.values.indexed)
                Expanded(
                  child: _VorynBottomNavigationItem(
                    tab: tab,
                    selected: index == currentIndex,
                    onPressed: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VorynBottomNavigationItem extends StatelessWidget {
  const _VorynBottomNavigationItem({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final VorynTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final itemColor = selected ? colors.accent : colors.textMuted;

    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      child: InkWell(
        onTap: onPressed,
        splashColor: colors.accentSoft,
        highlightColor: colors.surfacePressed,
        child: Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, color: itemColor, size: 24),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: itemColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VorynTabLanding extends StatelessWidget {
  const VorynTabLanding({super.key, required this.tab});

  final VorynTab tab;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(spacing.screen),
          children: [
            Row(
              children: [
                VorynAvatar(
                  initials: tab.label.substring(0, 1),
                  size: VorynAvatarSize.medium,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab.headline,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        tab.detail,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            VorynSurface(
              child: Row(
                children: [
                  Icon(tab.icon, color: colors.accent, size: 28),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tab.label} tab ready',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: spacing.xxs),
                        Text(
                          'Phase 1.2 verifies the app shell and navigation only.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.md),
            VorynCard(
              child: Row(
                children: [
                  const VorynPresenceIndicator(
                    status: VorynPresenceStatus.online,
                    label: 'Navigation active',
                  ),
                  const Spacer(),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colors.iconMuted,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              'Placeholder content only',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'The real ${tab.label} UI is reserved for its later authorized checkpoint.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
