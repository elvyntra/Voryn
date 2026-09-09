import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';

class OnboardingData {
  String fullName = 'Vikash Mishra';
  String email = 'vikash@example.com';
  String countryCode = '+91';
  String phone = '98765 43210';
  bool phoneVerified = false;
  bool avatarSelected = false;
  String vorynId = '';
}

final onboardingData = OnboardingData();

class OnboardingShell extends StatelessWidget {
  const OnboardingShell({super.key, required this.step, required this.child});

  final int step;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: FocusScope.of(context).unfocus,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                spacing.screen,
                spacing.sm,
                spacing.screen,
                spacing.lg,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - spacing.sm - spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Semantics(
                          button: true,
                          label: 'Back',
                          child: IconButton(
                            tooltip: 'Back',
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          ),
                        ),
                        Text(
                          'Step $step of 3',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.lg),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  String? _nameError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: onboardingData.fullName);
    _phone = TextEditingController(text: onboardingData.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _name.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _nameError = name.isEmpty ? 'Enter your full name' : null;
      _phoneError = digits.isEmpty
          ? 'Enter your phone number'
          : digits.length < 7
          ? 'Enter a valid phone number'
          : null;
    });
    if (_nameError != null || _phoneError != null) return;
    onboardingData.fullName = name;
    onboardingData.phone = _phone.text.trim();
    context.push('/onboarding/verify-phone');
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;
    return OnboardingShell(
      step: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Complete your profile',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            'Help people recognize you on VoRyn.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: spacing.xl),
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: colors.accentSoft,
                  child: onboardingData.avatarSelected
                      ? const Icon(Icons.person, size: 42)
                      : Text(
                          'VM',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: colors.accent),
                        ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: IconButton.filled(
                    tooltip: 'Choose profile photo',
                    onPressed: () => setState(
                      () => onboardingData.avatarSelected =
                          !onboardingData.avatarSelected,
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'Full name',
            controller: _name,
            prefixIcon: Icons.person_outline_rounded,
            errorText: _nameError,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _nameError = null),
          ),
          SizedBox(height: spacing.md),
          VorynTextInput(
            label: 'Email',
            controller: TextEditingController(text: onboardingData.email),
            enabled: false,
            prefixIcon: Icons.alternate_email_rounded,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: colors.success, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Verified',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.success),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          SizedBox(height: spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: VorynTextInput(
                  label: 'Code',
                  controller: TextEditingController(
                    text: onboardingData.countryCode,
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: VorynTextInput(
                  label: 'Phone number',
                  controller: _phone,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  errorText: _phoneError,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _phoneError = null),
                  onSubmitted: (_) => _continue(),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxl),
          VorynButton.primary(label: 'Continue', onPressed: _continue),
        ],
      ),
    );
  }
}

class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _otp = TextEditingController();
  String? _error;
  bool _checking = false;
  int _resendSeconds = 28;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _resendSeconds > 0) setState(() => _resendSeconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_otp.text.length != 6) {
      setState(() => _error = 'Enter the 6-digit verification code');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (_otp.text != '123456') {
      setState(() {
        _checking = false;
        _error = 'Incorrect verification code';
      });
      return;
    }
    onboardingData.phoneVerified = true;
    setState(() => _checking = false);
    context.push('/onboarding/voryn-id');
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    return OnboardingShell(
      step: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verify your number',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            'We sent a 6-digit verification code to ${onboardingData.countryCode} ${onboardingData.phone}.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: spacing.xxl),
          TextField(
            controller: _otp,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _verify(),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(letterSpacing: 10),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              counterText: '',
              hintText: '• • • • • •',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.vorynColors.danger),
              ),
            ),
          SizedBox(height: spacing.lg),
          Center(
            child: _resendSeconds > 0
                ? Text(
                    'Resend in 00:${_resendSeconds.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.labelMedium,
                  )
                : TextButton(
                    onPressed: () {
                      setState(() {
                        _resendSeconds = 28;
                        _error = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Verification code sent')),
                      );
                    },
                    child: const Text('Resend code'),
                  ),
          ),
          Center(
            child: TextButton(
              onPressed: () => context.pop(),
              child: const Text('Change number'),
            ),
          ),
          SizedBox(height: spacing.xxl),
          VorynButton.primary(
            label: 'Verify',
            isLoading: _checking,
            onPressed: _checking || _otp.text.length != 6 ? null : _verify,
          ),
        ],
      ),
    );
  }
}

class CreateVorynIdScreen extends StatefulWidget {
  const CreateVorynIdScreen({super.key});

  @override
  State<CreateVorynIdScreen> createState() => _CreateVorynIdScreenState();
}

class _CreateVorynIdScreenState extends State<CreateVorynIdScreen> {
  final _username = TextEditingController();
  Timer? _debounce;
  String? _state;
  bool _checking = false;
  static const _taken = {'rahul', 'admin', 'support', 'voryn', 'test'};

  @override
  void dispose() {
    _debounce?.cancel();
    _username.dispose();
    super.dispose();
  }

  void _check(String value) {
    _debounce?.cancel();
    setState(() {
      _state = null;
      _checking = value.isNotEmpty;
    });
    if (value.isEmpty) {
      setState(() => _checking = false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final normalized = value.replaceFirst('@', '').toLowerCase();
      final valid =
          RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(normalized) &&
          normalized.length >= 3 &&
          normalized.length <= 24;
      if (!mounted) return;
      setState(() {
        _checking = false;
        _state = !valid
            ? 'invalid'
            : _taken.contains(normalized)
            ? 'taken'
            : 'available';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    final colors = context.vorynColors;
    final normalized = _username.text.replaceFirst('@', '').toLowerCase();
    final available = _state == 'available' && !_checking;
    final message = switch (_state) {
      'available' => '@$normalized is available',
      'taken' => 'This VoRyn ID is already taken',
      'invalid' =>
        normalized.length < 3
            ? 'Use at least 3 characters'
            : normalized.length > 24
            ? 'Use 24 characters or fewer'
            : 'Use letters, numbers and underscores only',
      _ => 'Choose a unique VoRyn ID.',
    };
    final messageColor = _state == 'available'
        ? colors.success
        : _state == null
        ? colors.textMuted
        : colors.danger;
    return OnboardingShell(
      step: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create your VoRyn ID',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SizedBox(height: spacing.sm),
          Text(
            'This is how people can find and call you on VoRyn.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SizedBox(height: spacing.xl),
          Center(
            child: Icon(
              Icons.alternate_email_rounded,
              color: colors.accent,
              size: 42,
            ),
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'VoRyn ID',
            controller: _username,
            hintText: 'vikash',
            prefixIcon: Icons.alternate_email_rounded,
            isLoading: _checking,
            textInputAction: TextInputAction.done,
            onChanged: _check,
          ),
          SizedBox(height: spacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Row(
              key: ValueKey(message),
              children: [
                Icon(
                  _state == 'available'
                      ? Icons.check_circle
                      : _state == null
                      ? Icons.info_outline
                      : Icons.error_outline,
                  color: messageColor,
                  size: 17,
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    _checking ? 'Checking...' : message,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: messageColor),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          VorynSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colors.iconMuted, size: 18),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    'People can also find you using your verified phone or email.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.xxl),
          VorynButton.primary(
            label: 'Create VoRyn ID',
            onPressed: available
                ? () {
                    onboardingData.vorynId = normalized;
                    context.go('/connect');
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
