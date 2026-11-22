import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signs in with a name and an optional password; a name no one has yet
/// makes a new account (AccountRepository.enter). Pops `true` once signed
/// in, so the screen that asked can go on with what it was doing.
///
/// With [onDone] it is the first-run step instead: it offers "Later", has no
/// back arrow, and calls [onDone] rather than popping, whether the person
/// signed in or skipped.
class SignInScreen extends StatefulWidget {
  final void Function(BuildContext context)? onDone;

  const SignInScreen({super.key, this.onDone});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _account = locator<AccountRepository>();
  final _name = TextEditingController();
  final _password = TextEditingController();

  bool get _firstRun => widget.onDone != null;

  bool _busy = false;
  // Visible by default: the password only tells family members apart.
  bool _showPassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.of(context);
    if (AccountRepository.isNameEmpty(_name.text)) {
      setState(() => _error = s.familyNameEmpty);
      return;
    }
    if (AccountRepository.isNameTooLong(_name.text)) {
      setState(
        () => _error = s.familyNameTooLong(AccountRepository.maxNameLength),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.enter(_name.text, _password.text);
      if (mounted) _finish(signedIn: true);
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
    return switch (error.code) {
      'wrong_password' => s.familyWrongPassword,
      'signup_disabled' ||
      'email_provider_disabled' ||
      'email_not_confirmed' => s.familySignUpUnavailable,
      _ => familyErrorText(s, error),
    };
  }

  void _finish({required bool signedIn}) {
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone(context);
    } else {
      Navigator.of(context).pop(signedIn);
    }
  }

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
        automaticallyImplyLeading: !_firstRun,
        title: Text(s.familySignInTitle),
        actions: [
          if (_firstRun)
            Semantics(
              identifier: 'family-sign-in-later',
              child: TextButton(
                onPressed: _busy ? null : () => _finish(signedIn: false),
                child: Text(s.familyLaterAction),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dimens.spacing20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.familySignInHeading, style: text.headlineSmall),
              const SizedBox(height: Dimens.spacing8),
              Text(
                s.familySignInBody,
                style: text.bodyMedium?.copyWith(color: muted),
              ),
              if (_firstRun) ...[
                const SizedBox(height: Dimens.spacing8),
                Text(
                  s.familyFirstRunNote,
                  style: text.bodyMedium?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: Dimens.spacing24),
              Semantics(
                identifier: 'family-sign-in-name',
                child: TextField(
                  controller: _name,
                  enabled: !_busy,
                  autofocus: true,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearError(),
                  decoration: InputDecoration(
                    labelText: s.familyPersonNameLabel,
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
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => _clearError(),
                  decoration: InputDecoration(
                    labelText: s.familyPasswordLabel,
                    helperText: s.familyPasswordHint,
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
                  child: BusyLabel(busy: _busy, label: s.familySignInAction),
                ),
              ),
            ],
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
