import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_button.dart';
import '../../shared/widgets/voryn_card.dart';
import '../../shared/widgets/voryn_text_input.dart';
import 'voryn_auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final auth = const VorynAuthService();
      final user = auth.currentSession?.user;
      context.go(
        user == null ? '/welcome' : auth.routeAfterAuthentication(user),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.backgroundSoft, colors.background],
          ),
        ),
        child: Center(child: VorynBrandMark(size: 86)),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(child: VorynBrandMark(size: 76)),
          SizedBox(height: spacing.lg),
          Text(
            'Voryn',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayLarge,
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Connect your way.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.textSecondary),
          ),
          const Spacer(),
          VorynButton.secondary(
            label: 'Continue with Google',
            leadingIcon: Icons.g_mobiledata_rounded,
            onPressed: () async {
              final result = await const VorynAuthService().signInWithGoogle();
              if (context.mounted && result.error != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.error!)));
              }
            },
          ),
          SizedBox(height: spacing.md),
          VorynButton.primary(
            label: 'Sign in with email',
            leadingIcon: Icons.mail_outline_rounded,
            onPressed: () => context.go('/sign-in'),
          ),
          SizedBox(height: spacing.sm),
          TextButton(
            onPressed: () => context.go('/sign-up'),
            child: const Text('Create an account'),
          ),
          SizedBox(height: spacing.lg),
          Text(
            'By continuing, you agree to Voryn\'s Terms and Privacy Policy.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _auth = const VorynAuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = _email.text.contains('@') ? null : 'Enter a valid email.';
      _passwordError = _password.text.length >= 6
          ? null
          : 'Password must be at least 6 characters.';
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _loading = true);
    final result = await _auth.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _loading = false;
        _passwordError = result.error;
      });
      return;
    }
    final user = result.user;
    if (user == null) {
      setState(() {
        _loading = false;
        _passwordError = 'Sign in did not return a user. Please try again.';
      });
      return;
    }
    context.go(_auth.routeAfterAuthentication(user));
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    final result = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.error != null) {
      setState(() {
        _passwordError = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return AuthScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Welcome back',
            subtitle: 'Sign in with your email to continue to Voryn.',
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'Email',
            controller: _email,
            hintText: 'you@example.com',
            prefixIcon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
            errorText: _emailError,
            onChanged: (_) => setState(() => _emailError = null),
          ),
          SizedBox(height: spacing.md),
          VorynTextInput(
            label: 'Password',
            controller: _password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _hidePassword,
            textInputAction: TextInputAction.done,
            enabled: !_loading,
            errorText: _passwordError,
            onChanged: (_) => setState(() => _passwordError = null),
            onSubmitted: (_) => _submit(),
            suffixIcon: IconButton(
              onPressed: _loading
                  ? null
                  : () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : () => context.go('/forgot-password'),
              child: const Text('Forgot password?'),
            ),
          ),
          SizedBox(height: spacing.md),
          VorynButton.primary(
            label: 'Sign in',
            isLoading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          SizedBox(height: spacing.md),
          VorynButton.secondary(
            label: 'Continue with Google',
            leadingIcon: Icons.g_mobiledata_rounded,
            onPressed: _loading ? null : _signInWithGoogle,
          ),
          const Spacer(),
          AuthSwitchLink(
            prompt: 'New to Voryn?',
            action: 'Create account',
            onPressed: _loading ? null : () => context.go('/sign-up'),
          ),
        ],
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _auth = const VorynAuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _confirmationEmail;
  final _otp = TextEditingController();
  String? _otpError;
  bool _verifyingOtp = false;
  bool _resendingOtp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = _email.text.contains('@') ? null : 'Enter a valid email.';
      _passwordError = _password.text.length >= 6
          ? null
          : 'Use 6 or more characters.';
      _confirmError = _confirmPassword.text == _password.text
          ? null
          : 'Passwords do not match.';
    });
    if (_emailError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }

    setState(() => _loading = true);
    final result = await _auth.signUp(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _loading = false;
        _passwordError = result.error;
      });
      return;
    }
    if (result.accountAlreadyExists) {
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Account already exists'),
          content: const Text(
            'This email is already connected to Voryn. Sign in with Google, or use Forgot password to create a password for email sign-in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/welcome');
      return;
    }
    if (result.emailConfirmationRequired) {
      setState(() {
        _loading = false;
        _confirmationEmail = _email.text.trim();
      });
      return;
    }
    final user = result.user;
    if (user == null) {
      setState(() {
        _loading = false;
        _passwordError = 'Account creation did not return a user.';
      });
      return;
    }
    context.go('/onboarding/profile');
  }

  Future<void> _verifyEmail() async {
    if (_otp.text.trim().length != 6) {
      setState(() => _otpError = 'Enter the 6-digit email code.');
      return;
    }
    setState(() {
      _verifyingOtp = true;
      _otpError = null;
    });
    final result = await _auth.verifyEmailOtp(
      email: _confirmationEmail!,
      token: _otp.text.trim(),
    );
    if (!mounted) return;
    if (!result.isSuccess || result.user == null) {
      setState(() {
        _verifyingOtp = false;
        _otpError = result.error ?? 'Could not verify this email code.';
      });
      return;
    }
    context.go('/onboarding/profile');
  }

  Future<void> _resendEmailOtp() async {
    setState(() {
      _resendingOtp = true;
      _otpError = null;
    });
    final result = await _auth.resendSignupOtp(_confirmationEmail!);
    if (!mounted) return;
    setState(() => _resendingOtp = false);
    if (result.error != null) {
      setState(() => _otpError = result.error);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('A new email code was sent.')));
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _loading = true);
    final result = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.error != null) {
      setState(() {
        _passwordError = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    if (_confirmationEmail != null) {
      return AuthScaffold(
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Icon(Icons.password_rounded, size: 56),
            SizedBox(height: spacing.lg),
            Text(
              'Enter your email code',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: spacing.sm),
            Text(
              'Enter the 6-digit code sent to $_confirmationEmail.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: spacing.lg),
            VorynTextInput(
              label: 'Email code',
              controller: _otp,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              enabled: !_verifyingOtp && !_resendingOtp,
              errorText: _otpError,
              onChanged: (_) => setState(() => _otpError = null),
              onSubmitted: (_) => _verifyEmail(),
            ),
            SizedBox(height: spacing.md),
            VorynButton.primary(
              label: 'Verify email',
              isLoading: _verifyingOtp,
              onPressed: _verifyingOtp || _resendingOtp ? null : _verifyEmail,
            ),
            TextButton(
              onPressed: _verifyingOtp || _resendingOtp
                  ? null
                  : _resendEmailOtp,
              child: Text(_resendingOtp ? 'Sending...' : 'Resend code'),
            ),
            const Spacer(),
            VorynButton.primary(
              label: 'Back to sign in',
              onPressed: () => context.go('/sign-in'),
            ),
          ],
        ),
      );
    }

    return AuthScaffold(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Create account',
            subtitle:
                'Start with email and password. Profile setup comes later.',
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'Email',
            controller: _email,
            hintText: 'you@example.com',
            prefixIcon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
            errorText: _emailError,
            onChanged: (_) => setState(() => _emailError = null),
          ),
          SizedBox(height: spacing.md),
          VorynTextInput(
            label: 'Password',
            controller: _password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _hidePassword,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
            errorText: _passwordError,
            onChanged: (_) => setState(() => _passwordError = null),
            suffixIcon: IconButton(
              onPressed: _loading
                  ? null
                  : () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          SizedBox(height: spacing.md),
          VorynTextInput(
            label: 'Confirm password',
            controller: _confirmPassword,
            prefixIcon: Icons.verified_user_outlined,
            obscureText: _hidePassword,
            textInputAction: TextInputAction.done,
            enabled: !_loading,
            errorText: _confirmError,
            onChanged: (_) => setState(() => _confirmError = null),
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: spacing.lg),
          VorynButton.primary(
            label: 'Create account',
            isLoading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          SizedBox(height: spacing.md),
          VorynButton.secondary(
            label: 'Continue with Google',
            leadingIcon: Icons.g_mobiledata_rounded,
            onPressed: _loading ? null : _signUpWithGoogle,
          ),
          const Spacer(),
          AuthSwitchLink(
            prompt: 'Already have an account?',
            action: 'Sign in',
            onPressed: _loading ? null : () => context.go('/sign-in'),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _auth = const VorynAuthService();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;
  String? _passwordError;
  String? _confirmationError;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _passwordError = _password.text.length >= 6
          ? null
          : 'Use 6 or more characters.';
      _confirmationError = _confirmation.text == _password.text
          ? null
          : 'Passwords do not match.';
    });
    if (_passwordError != null || _confirmationError != null) return;

    setState(() => _loading = true);
    final result = await _auth.updatePassword(_password.text);
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _loading = false;
        _passwordError = result.error;
      });
      return;
    }
    final user = result.user;
    context.go(
      user == null ? '/sign-in' : _auth.routeAfterAuthentication(user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            title: 'Create new password',
            subtitle: 'Choose a password you can use to sign in with email.',
          ),
          SizedBox(height: spacing.xl),
          VorynTextInput(
            label: 'New password',
            controller: _password,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _hidePassword,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
            errorText: _passwordError,
            onChanged: (_) => setState(() => _passwordError = null),
            suffixIcon: IconButton(
              onPressed: _loading
                  ? null
                  : () => setState(() => _hidePassword = !_hidePassword),
              icon: Icon(
                _hidePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          SizedBox(height: spacing.md),
          VorynTextInput(
            label: 'Confirm new password',
            controller: _confirmation,
            prefixIcon: Icons.verified_user_outlined,
            obscureText: _hidePassword,
            textInputAction: TextInputAction.done,
            enabled: !_loading,
            errorText: _confirmationError,
            onChanged: (_) => setState(() => _confirmationError = null),
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: spacing.lg),
          VorynButton.primary(
            label: 'Save password',
            isLoading: _loading,
            onPressed: _loading ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = const VorynAuthService();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailError = _email.text.contains('@') ? null : 'Enter a valid email.';
    });
    if (_emailError != null) return;

    setState(() => _loading = true);
    final result = await _auth.sendPasswordReset(_email.text.trim());
    if (mounted) {
      setState(() {
        _loading = false;
        _emailError = result.error;
        _sent = result.isSuccess;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;

    return AuthScaffold(
      showBack: true,
      child: _sent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                VorynSurface(
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: colors.success.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mark_email_read_outlined,
                          color: colors.success,
                          size: 32,
                        ),
                      ),
                      SizedBox(height: spacing.lg),
                      Text(
                        'Check your email',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      SizedBox(height: spacing.sm),
                      Text(
                        'We sent a reset link to ${_email.text}.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                VorynButton.primary(
                  label: 'Back to sign in',
                  onPressed: () => context.go('/sign-in'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(
                  title: 'Reset password',
                  subtitle:
                      'Enter your email and we will show the check-email state.',
                ),
                SizedBox(height: spacing.xl),
                VorynTextInput(
                  label: 'Email',
                  controller: _email,
                  hintText: 'you@example.com',
                  prefixIcon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  enabled: !_loading,
                  isLoading: _loading,
                  errorText: _emailError,
                  onChanged: (_) => setState(() => _emailError = null),
                  onSubmitted: (_) => _submit(),
                ),
                SizedBox(height: spacing.lg),
                VorynButton.primary(
                  label: 'Send reset link',
                  isLoading: _loading,
                  onPressed: _loading ? null : _submit,
                ),
              ],
            ),
    );
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.showBack = false});

  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.background,
              colors.backgroundSoft,
              colors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.screen,
                  spacing.md,
                  spacing.screen,
                  spacing.screen,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - spacing.screen,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 44,
                          child: showBack
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    onPressed: () => context.go('/welcome'),
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final spacing = context.vorynSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VorynBrandMark(size: 48),
        SizedBox(height: spacing.xl),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        SizedBox(height: spacing.sm),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class VorynBrandMark extends StatelessWidget {
  const VorynBrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final brightness = Theme.of(context).brightness;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        brightness == Brightness.dark
            ? 'assets/branding/voryn_app_logo_dark.png'
            : 'assets/branding/voryn_app_logo_light.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Voryn logo',
      ),
    );
  }
}

class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }
}
