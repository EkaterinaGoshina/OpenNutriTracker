import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';
import 'package:opennutritracker/features/family/domain/family_invite_link.dart';
import 'package:opennutritracker/features/family/domain/pending_family_invite.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Joins a family by invite code. The code from an invite link the app was
/// opened with is filled in. Pops `true` once the person is in a family, which
/// includes finding out they already were.
class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _repository = locator<FamilyRepository>();
  late final _code = TextEditingController(
    text: locator.isRegistered<PendingFamilyInvite>()
        ? locator<PendingFamilyInvite>().code ?? ''
        : '',
  );

  bool _busy = false;
  String? _error;
  bool _alreadyInFamily = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final s = S.of(context);
    // A code with the wrong shape cannot exist, so say so without a request.
    final code = FamilyInviteLink.normalize(_code.text);
    if (code == null) {
      setState(() => _error = s.familyErrorInviteNotFound);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _alreadyInFamily = false;
    });
    try {
      await _repository.joinFamily(code);
      if (locator.isRegistered<PendingFamilyInvite>()) {
        locator<PendingFamilyInvite>().clear();
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e is FamilyException && e.error == FamilyError.alreadyInFamily) {
          _alreadyInFamily = true;
        } else {
          _error = familyErrorText(s, e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.familyJoinTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dimens.spacing20),
          child: _alreadyInFamily
              ? _alreadyIn(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.familyJoinHeading, style: text.headlineSmall),
                    const SizedBox(height: Dimens.spacing8),
                    Text(
                      s.familyJoinBody,
                      style: text.bodyMedium?.copyWith(
                        color: paletteOf(context).textMuted,
                      ),
                    ),
                    const SizedBox(height: Dimens.spacing24),
                    Semantics(
                      identifier: 'family-join-code',
                      child: TextField(
                        controller: _code,
                        enabled: !_busy,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _join(),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        style: text.titleLarge?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                        decoration: InputDecoration(
                          labelText: s.familyCodeFieldLabel,
                          errorText: _error,
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: Dimens.spacing16),
                    Semantics(
                      identifier: 'family-join-submit',
                      child: FilledButton(
                        onPressed: _busy ? null : _join,
                        child: BusyLabel(
                          busy: _busy,
                          label: s.familyJoinAction,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _alreadyIn(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.groups_rounded, size: 40, color: paletteOf(context).carbs),
          const SizedBox(height: Dimens.spacing12),
          Text(
            s.familyAlreadyInFamilyTitle,
            textAlign: TextAlign.center,
            style: text.titleLarge,
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            s.familyAlreadyInFamilyBody,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: paletteOf(context).textMuted,
            ),
          ),
          const SizedBox(height: Dimens.spacing16),
          Semantics(
            identifier: 'family-join-open-mine',
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.familyOpenMyFamilyAction),
            ),
          ),
        ],
      ),
    );
  }
}
