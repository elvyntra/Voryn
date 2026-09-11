import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';

const vorynOAuthRedirectUrl = 'io.supabase.voryn://login-callback/';
const _backendUnavailableMessage =
    'Voryn could not connect to authentication. Please try again.';

class VorynAuthResult {
  const VorynAuthResult({
    this.user,
    this.error,
    this.emailConfirmationRequired = false,
    this.accountAlreadyExists = false,
  });

  final User? user;
  final String? error;
  final bool emailConfirmationRequired;
  final bool accountAlreadyExists;

  bool get isSuccess => error == null;
}

class VorynAuthService {
  const VorynAuthService();

  SupabaseClient? get _client => VorynBackend.client;

  bool get isAvailable => _client != null;

  Session? get currentSession => _client?.auth.currentSession;

  Stream<AuthState> get authStateChanges =>
      _client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

  Future<VorynAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return VorynAuthResult(user: response.user);
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return const VorynAuthResult(
          error:
              'Incorrect email or password. If you joined with Google, continue with Google or use Forgot password to create a password.',
        );
      }
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
  }

  Future<VorynAuthResult> signUp({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
      );
      final accountAlreadyExists =
          response.user != null && response.user!.identities?.isEmpty == true;
      return VorynAuthResult(
        user: response.user,
        accountAlreadyExists: accountAlreadyExists,
        emailConfirmationRequired:
            !accountAlreadyExists && response.session == null,
      );
    } on AuthException catch (error) {
      if (error.message.toLowerCase().contains('already registered')) {
        return const VorynAuthResult(accountAlreadyExists: true);
      }
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
  }

  Future<VorynAuthResult> sendPasswordReset(String email) async {
    final client = _client;
    if (client == null) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
    try {
      await client.auth.resetPasswordForEmail(
        email,
        redirectTo: vorynOAuthRedirectUrl,
      );
      return const VorynAuthResult();
    } on AuthException catch (error) {
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
  }

  Future<VorynAuthResult> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final client = _client;
    if (client == null) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
    try {
      final response = await client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
      return VorynAuthResult(user: response.user);
    } on AuthException catch (error) {
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(error: 'Could not verify this email code.');
    }
  }

  Future<VorynAuthResult> resendSignupOtp(String email) async {
    final client = _client;
    if (client == null) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
    try {
      await client.auth.resend(type: OtpType.signup, email: email);
      return const VorynAuthResult();
    } on AuthException catch (error) {
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(error: 'Could not resend the email code.');
    }
  }

  Future<VorynAuthResult> updatePassword(String password) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) {
      return const VorynAuthResult(
        error: 'This password link has expired. Request a new one.',
      );
    }
    try {
      final response = await client.auth.updateUser(
        UserAttributes(password: password),
      );
      return VorynAuthResult(user: response.user);
    } on AuthException catch (error) {
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
  }

  Future<VorynAuthResult> signInWithGoogle() async {
    final client = _client;
    if (client == null) {
      return const VorynAuthResult(error: _backendUnavailableMessage);
    }
    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: vorynOAuthRedirectUrl,
      );
      return launched
          ? const VorynAuthResult()
          : const VorynAuthResult(
              error: 'Could not open Google sign in. Please try again.',
            );
    } on AuthException catch (error) {
      return VorynAuthResult(error: error.message);
    } catch (_) {
      return const VorynAuthResult(
        error: 'Could not open Google sign in. Please try again.',
      );
    }
  }

  String routeAfterAuthentication(User user) {
    final completed = user.userMetadata?['onboarding_completed'] == true;
    return completed ? '/connect' : '/onboarding/profile';
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }
}
