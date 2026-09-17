import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../auth/auth_screens.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.hub_outlined,
      eyebrow: 'A clearer way to connect',
      title: 'Your people, in one place.',
      body:
          'Voryn brings calling, messaging, contacts, and meetings into one calm, focused space.',
    ),
    (
      icon: Icons.person_search_outlined,
      eyebrow: 'Find people faster',
      title: 'Connect by what you know.',
      body:
          'Use a Voryn ID or phone number to reach the right person without digging through scattered apps.',
    ),
    (
      icon: Icons.lock_outline_rounded,
      eyebrow: 'Designed around trust',
      title: 'Private by default.',
      body:
          'You control how people discover you, while permissions stay in your hands from the very first moment.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('voryn.landing.completed', true);
    if (!mounted) return;
    context.go('/welcome');
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.screen,
            spacing.md,
            spacing.screen,
            spacing.sm,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const VorynBrandMark(size: 34),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.xl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          VorynCard(
                            padding: EdgeInsets.all(spacing.xl),
                            child: Icon(
                              page.icon,
                              size: 78,
                              color: colors.accent,
                            ),
                          ),
                          SizedBox(height: spacing.xl),
                          Text(
                            page.eyebrow.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colors.accent,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          SizedBox(height: spacing.sm),
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          SizedBox(height: spacing.md),
                          Text(
                            page.body,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < _pages.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 6,
                      width: index == _page ? 24 : 6,
                      decoration: BoxDecoration(
                        color: index == _page ? colors.accent : colors.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
              SizedBox(height: spacing.md),
              VorynButton.primary(
                label: _page == _pages.length - 1 ? 'Get started' : 'Continue',
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
