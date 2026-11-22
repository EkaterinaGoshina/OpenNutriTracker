import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in to our Supabase project. An account exists only for the family:
/// without one the app keeps working fully offline.
///
/// People sign in with a login and a password, no email. Supabase only takes
/// passwords with an email, so the login becomes a stand-in address on
/// [loginDomain]; no mail is ever sent to it. The project must have
/// "Confirm email" turned off, or sign-up would wait for a letter that never
/// comes (supabase/README.md).
class AccountRepository {
  /// The domain of the stand-in addresses. It is our own site, which has no
  /// mail server, so a letter sent by mistake reaches no one.
  static const loginDomain = 'opennutritracker.goshina.workers.dev';

  static const minLoginLength = 3;
  static const maxLoginLength = 32;

  /// Supabase's default minimum.
  static const minPasswordLength = 6;

  static final _loginPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

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

  /// Logins are case-insensitive: `Katya` and `katya` are one account.
  static String normalizeLogin(String login) => login.trim().toLowerCase();

  /// Latin letters, digits, dot, dash and underscore, starting with a letter
  /// or digit: the part of an address before `@` that Supabase accepts.
  static bool isValidLogin(String login) {
    final value = normalizeLogin(login);
    return value.length >= minLoginLength &&
        value.length <= maxLoginLength &&
        _loginPattern.hasMatch(value);
  }

  static String emailForLogin(String login) =>
      '${normalizeLogin(login)}@$loginDomain';

  /// What to show as "signed in as": the login for a login account, the
  /// address for a Google one.
  static String displayName(String email) {
    const suffix = '@$loginDomain';
    return email.endsWith(suffix)
        ? email.substring(0, email.length - suffix.length)
        : email;
  }

  Future<User?> signIn(String login, String password) async {
    final response = await _auth.signInWithPassword(
      email: emailForLogin(login),
      password: password,
    );
    return response.user;
  }

  /// Creates the account and signs in. Throws [AuthException] with code
  /// `user_already_exists` when the login is taken.
  Future<User?> signUp(String login, String password) async {
    final response = await _auth.signUp(
      email: emailForLogin(login),
      password: password,
      data: {'name': normalizeLogin(login)},
    );
    if (response.session == null) {
      // The project still asks to confirm the email: the account exists but
      // cannot sign in until "Confirm email" is turned off.
      throw const AuthException(
        'Email confirmation is on',
        code: 'email_not_confirmed',
      );
    }
    return response.user;
  }

  /// Leaves the page for Google's sign-in and comes back to [returnTo], so a
  /// `?join=` code in it survives the round trip.
  Future<void> signInWithGoogle({required Uri returnTo}) => _auth
      .signInWithOAuth(OAuthProvider.google, redirectTo: returnTo.toString());

  /// Signs out on this device only; other devices keep their sessions.
  Future<void> signOut() => _auth.signOut(scope: SignOutScope.local);
}
