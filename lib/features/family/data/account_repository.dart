import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in to our Supabase project. An account exists only for the family:
/// without one the app keeps working fully offline.
///
/// Email sign-in uses a six-digit code rather than a magic link, so it works
/// the same in a browser and in the mobile apps without deep links. The
/// project's "Magic Link" email template has to include `{{ .Token }}`
/// (supabase/README.md).
class AccountRepository {
  final GoTrueClient _auth;

  AccountRepository(this._auth);

  User? get currentUser => _auth.currentUser;

  /// Emits on sign-in, sign-out and token refresh, starting with the
  /// session restored at launch.
  Stream<User?> get userChanges =>
      _auth.onAuthStateChange.map((state) => state.session?.user);

  /// Google returns to the page through a browser redirect, which only the
  /// web build handles so far; the mobile apps would need a deep link.
  bool get supportsGoogle => kIsWeb;

  Future<void> sendEmailCode(String email) =>
      _auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);

  Future<User?> verifyEmailCode(String email, String code) async {
    final response = await _auth.verifyOTP(
      type: OtpType.email,
      email: email.trim(),
      token: code.trim(),
    );
    return response.user;
  }

  /// Leaves the page for Google's sign-in and comes back to [returnTo], so a
  /// `?join=` code in it survives the round trip.
  Future<void> signInWithGoogle({required Uri returnTo}) => _auth
      .signInWithOAuth(OAuthProvider.google, redirectTo: returnTo.toString());

  /// Signs out on this device only; other devices keep their sessions.
  Future<void> signOut() => _auth.signOut(scope: SignOutScope.local);
}
