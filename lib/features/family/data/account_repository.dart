import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in to our Supabase project. An account exists only for the family:
/// without one the app keeps working fully offline.
///
/// The account only tells family members apart, so it asks for a name and an
/// optional password, nothing else. Supabase wants an email and a password of
/// at least six characters, so both are made up here:
///
/// - the name, any letters, becomes a stand-in address on [loginDomain]
///   (base32 of its UTF-8, since an address takes only Latin letters); no
///   mail is ever sent to it;
/// - the password the person typed, even an empty one, gets a fixed prefix.
///
/// The project must have "Confirm email" turned off, or a new account would
/// wait for a letter that never comes (supabase/README.md).
class AccountRepository {
  /// The domain of the stand-in addresses. It is our own site, which has no
  /// mail server, so a letter sent by mistake reaches no one.
  static const loginDomain = 'opennutritracker.goshina.workers.dev';

  static const maxNameLength = 20;

  /// The part of an address before `@` holds at most 64 characters, which is
  /// base32 of 40 bytes: twenty Cyrillic letters.
  static const _maxNameBytes = 40;
  static const _passwordPrefix = 'ont-family:';

  final GoTrueClient _auth;

  AccountRepository(this._auth);

  User? get currentUser => _auth.currentUser;

  /// Emits on sign-in, sign-out and token refresh, starting with the
  /// session restored at launch.
  Stream<User?> get userChanges =>
      _auth.onAuthStateChange.map((state) => state.session?.user);

  /// Names are case-insensitive and ignore extra spaces: ` Катя ` and
  /// `катя` are one account.
  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static bool isNameEmpty(String name) => normalizeName(name).isEmpty;

  static bool isNameTooLong(String name) {
    final value = normalizeName(name);
    return value.runes.length > maxNameLength ||
        utf8.encode(value).length > _maxNameBytes;
  }

  static String emailForName(String name) =>
      '${_base32(utf8.encode(normalizeName(name)))}@$loginDomain';

  static String passwordFor(String password) => '$_passwordPrefix$password';

  /// What to show as "signed in as": the name, or the whole address for an
  /// account made some other way.
  static String displayName(String email) {
    const suffix = '@$loginDomain';
    if (!email.endsWith(suffix)) return email;
    final encoded = email.substring(0, email.length - suffix.length);
    try {
      return utf8.decode(_unbase32(encoded));
    } on FormatException {
      return email;
    }
  }

  /// Signs in, or creates the account if no one has this name yet. Throws
  /// [AuthException] with code `wrong_password` when the name is taken and
  /// the password does not match.
  Future<User?> enter(String name, String password) async {
    final email = emailForName(name);
    final secret = passwordFor(password);
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: secret,
      );
      return response.user;
    } on AuthException catch (e) {
      if (!_isWrongCredentials(e)) rethrow;
    }
    try {
      final response = await _auth.signUp(
        email: email,
        password: secret,
        data: {'name': name.trim()},
      );
      if (response.session == null) {
        // The project still asks to confirm the email: the account exists
        // but cannot sign in until "Confirm email" is turned off.
        throw const AuthException(
          'Email confirmation is on',
          code: 'email_not_confirmed',
        );
      }
      return response.user;
    } on AuthException catch (e) {
      if (e.code == 'user_already_exists' || e.code == 'email_exists') {
        throw const AuthException('Wrong password', code: 'wrong_password');
      }
      rethrow;
    }
  }

  /// Before error codes, wrong credentials came back as a bare 400.
  static bool _isWrongCredentials(AuthException e) =>
      e.code == 'invalid_credentials' ||
      (e.code == null && e.statusCode == '400');

  /// Signs out on this device only; other devices keep their sessions.
  Future<void> signOut() => _auth.signOut(scope: SignOutScope.local);

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

  /// RFC 4648 base32, lowercase, without padding.
  static String _base32(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static List<int> _unbase32(String text) {
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final char in text.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) throw FormatException('Not base32', text);
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    return out;
  }
}
