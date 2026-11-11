import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signs in with a code emailed to the person, or with Google on the web.
/// Pops `true` once signed in, so the screen that asked can go on with what it
/// was doing.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const _codeLength = 6;
  static const _resendDelay = 60;

  final _account = locator<AccountRepository>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  Timer? _ticker;

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _secondsToResend = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailLooksValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _sendCode() async {
    final s = S.of(context);
    if (!_emailLooksValid) {
      setState(() => _error = s.familyEmailInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.sendEmailCode(_email.text);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _codeSent = true;
        _busy = false;
      });
      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = familyErrorText(s, e);
      });
    }
  }

  Future<void> _verify() async {
    final s = S.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.verifyEmailCode(_email.text, _code.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // A wrong or stale code is an AuthException; anything else is the
        // network, where retyping the code would not help.
        _error = e is AuthException
            ? s.familyCodeInvalid
            : familyErrorText(s, e);
      });
    }
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

  void _startResendTimer() {
    _ticker?.cancel();
    setState(() => _secondsToResend = _resendDelay);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsToResend <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsToResend = 0);
        return;
      }
      setState(() => _secondsToResend -= 1);
    });
  }

  void _changeEmail() {
    _ticker?.cancel();
    setState(() {
      _codeSent = false;
      _error = null;
      _secondsToResend = 0;
    });
  }

  String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_codeSent ? s.familyCodeTitle : s.familySignInTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dimens.spacing20),
          child: _codeSent ? _codeStep(context) : _emailStep(context),
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

  Widget _emailStep(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.familySignInHeading, style: text.headlineSmall),
        const SizedBox(height: Dimens.spacing8),
        Text(
          s.familySignInBody,
          style: text.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: Dimens.spacing24),
        Semantics(
          identifier: 'family-sign-in-email',
          child: TextField(
            controller: _email,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(labelText: s.familyEmailLabel),
          ),
        ),
        if (_error != null) _errorLine(context),
        const SizedBox(height: Dimens.spacing16),
        Semantics(
          identifier: 'family-sign-in-send-code',
          child: FilledButton(
            onPressed: _busy ? null : _sendCode,
            child: BusyLabel(busy: _busy, label: s.familySendCodeAction),
          ),
        ),
        if (_account.supportsGoogle) ...[
          const SizedBox(height: Dimens.spacing16),
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
    );
  }

  Widget _codeStep(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.familyCodeHeading, style: text.headlineSmall),
        const SizedBox(height: Dimens.spacing8),
        Text(
          s.familyCodeSentTo(_email.text.trim()),
          style: text.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: Dimens.spacing24),
        Semantics(
          identifier: 'family-sign-in-code',
          child: TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_codeLength),
            ],
            style: text.headlineMedium?.copyWith(letterSpacing: 10),
            onChanged: (value) {
              if (_error != null) setState(() => _error = null);
              if (value.length == _codeLength && !_busy) _verify();
            },
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing12),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_error != null) _errorLine(context),
        const SizedBox(height: Dimens.spacing16),
        if (_secondsToResend > 0)
          Text(
            s.familyResendIn(_clock(_secondsToResend)),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: muted),
          )
        else
          Semantics(
            identifier: 'family-sign-in-resend',
            child: OutlinedButton(
              onPressed: _busy ? null : _sendCode,
              child: Text(s.familyResendAction),
            ),
          ),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'family-sign-in-change-email',
          child: TextButton(
            onPressed: _busy ? null : _changeEmail,
            child: Text(s.familyChangeEmailAction),
          ),
        ),
      ],
    );
  }
}
