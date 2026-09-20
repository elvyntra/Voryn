import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/voryn_backend.dart';

const vorynOAuthRedirectUrl = 'io.supabase.voryn://login-callback/';
const _backendUnavailableMessage =
    'Could not reach Voryn. Check your internet connection and try again.';

String _friendlyAuthError(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('socketexception') ||
      normalized.contains('clientexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('network')) {
    return _backendUnavailableMessage;
  }
  return message;
}

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
      return VorynAuthResult(error: _friendlyAuthError(error.message));
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
      return VorynAuthResult(error: _friendlyAuthError(error.message));
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
      return VorynAuthResult(error: _friendlyAuthError(error.message));
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
      return VorynAuthResult(error: _friendlyAuthError(error.message));
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
      return VorynAuthResult(error: _friendlyAuthError(error.message));
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
      return VorynAuthResult(error: _friendlyAuthError(error.message));
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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final googleSignIn = GoogleSignIn(scopes: const ['email']);
        final account = await googleSignIn.signIn();
        if (account == null) {
          return const VorynAuthResult();
        }

        final authentication = await account.authentication;
        final idToken = authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          return const VorynAuthResult(
            error: 'Google did not return a valid sign-in token.',
          );
        }

        final response = await client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: authentication.accessToken,
        );
        return VorynAuthResult(user: response.user);
      }

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
    try {
      final preferences = await SharedPreferences.getInstance();
      final installationId = preferences.getString('voryn.installation.id');
      final user = _client?.auth.currentUser;
      if (_client != null && user != null) {
        if (installationId != null && installationId.isNotEmpty) {
          await _client!.from('user_devices').delete().match({
            'user_uid': user.id,
            'installation_id': installationId,
          });
        } else {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null && token.isNotEmpty) {
            await _client!.from('user_devices').delete().match({
              'user_uid': user.id,
              'push_token': token,
            });
          }
        }
      }
    } catch (_) {}
    await _client?.auth.signOut();
  }
}
