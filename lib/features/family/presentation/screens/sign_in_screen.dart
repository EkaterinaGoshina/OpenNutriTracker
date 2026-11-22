import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signs in with a login and a password, or with Google on the web. The same
/// screen creates an account. Pops `true` once signed in, so the screen that
/// asked can go on with what it was doing.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _account = locator<AccountRepository>();
  final _login = TextEditingController();
  final _password = TextEditingController();

  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.of(context);
    if (!AccountRepository.isValidLogin(_login.text)) {
      setState(() => _error = s.familyLoginInvalid);
      return;
    }
    if (_password.text.length < AccountRepository.minPasswordLength) {
      setState(
        () => _error = s.familyPasswordTooShort(
          AccountRepository.minPasswordLength,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await _account.signUp(_login.text, _password.text);
      } else {
        await _account.signIn(_login.text, _password.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(s, e);
      });
    }
  }

  String _errorText(S s, Object error) {
    if (error is! AuthException) return familyErrorText(s, error);
    switch (error.code) {
      case 'invalid_credentials':
        return s.familyWrongCredentials;
      case 'user_already_exists':
      case 'email_exists':
        return s.familyLoginTaken;
      case 'weak_password':
        return s.familyPasswordTooShort(AccountRepository.minPasswordLength);
      case 'signup_disabled':
      case 'email_provider_disabled':
      case 'email_not_confirmed':
        return s.familySignUpUnavailable;
    }
    // Before error codes, a wrong password came back as a bare 400.
    if (error.statusCode == '400' && !_creating) {
      return s.familyWrongCredentials;
    }
    return familyErrorText(s, error);
  }

  Future<void> _google() async {
    final s = S.of(context);
    setState(() => _error = null);
    try {
      await _account.signInWithGoogle(returnTo: Uri.base);
    } catch (e) {
      if (mounted) setState(() => _error = familyErrorText(s, e));
    }
  }

  void _toggleMode() => setState(() {
    _creating = !_creating;
    _error = null;
  });

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? s.familySignUpTitle : s.familySignInTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dimens.spacing20),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _creating ? s.familySignUpHeading : s.familySignInHeading,
                  style: text.headlineSmall,
                ),
                const SizedBox(height: Dimens.spacing8),
                Text(
                  _creating ? s.familySignUpBody : s.familySignInBody,
                  style: text.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: Dimens.spacing24),
                Semantics(
                  identifier: 'family-sign-in-login',
                  child: TextField(
                    controller: _login,
                    enabled: !_busy,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: [
                      _creating
                          ? AutofillHints.newUsername
                          : AutofillHints.username,
                    ],
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearError(),
                    decoration: InputDecoration(
                      labelText: s.familyLoginLabel,
                      helperText: _creating ? s.familyLoginHint : null,
                    ),
                  ),
                ),
                const SizedBox(height: Dimens.spacing12),
                Semantics(
                  identifier: 'family-sign-in-password',
                  child: TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      _creating
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => _clearError(),
                    decoration: InputDecoration(
                      labelText: s.familyPasswordLabel,
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? s.familyHidePasswordTooltip
                            : s.familyShowPasswordTooltip,
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                ),
                if (_error != null) _errorLine(context),
                const SizedBox(height: Dimens.spacing16),
                Semantics(
                  identifier: 'family-sign-in-submit',
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: BusyLabel(
                      busy: _busy,
                      label: _creating
                          ? s.familySignUpAction
                          : s.familySignInAction,
                    ),
                  ),
                ),
                const SizedBox(height: Dimens.spacing8),
                Semantics(
                  identifier: 'family-sign-in-toggle-mode',
                  child: TextButton(
                    onPressed: _busy ? null : _toggleMode,
                    child: Text(
                      _creating
                          ? s.familyToSignInAction
                          : s.familyToSignUpAction,
                    ),
                  ),
                ),
                if (_account.supportsGoogle) ...[
                  const SizedBox(height: Dimens.spacing8),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dimens.spacing12,
                        ),
                        child: Text(
                          s.familyOrDivider,
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: Dimens.spacing16),
                  Semantics(
                    identifier: 'family-sign-in-google',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.account_circle_outlined),
                      label: Text(s.familyGoogleAction),
                      onPressed: _busy ? null : _google,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorLine(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: color),
            const SizedBox(width: Dimens.spacing8),
            Expanded(
              child: Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
