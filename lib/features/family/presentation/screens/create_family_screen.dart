import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Names a new family and creates it, then shows the first invite code. Pops
/// `true` once the family exists, however the person leaves the screen.
class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key});

  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  static const _maxNameLength = 60;

  final _repository = locator<FamilyRepository>();
  final _name = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _created = false;
  FamilyInviteEntity? _invite;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final s = S.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = s.familyErrorInvalidName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.createFamily(name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = familyErrorText(s, e);
      });
      return;
    }
    // The family exists from here on: a failed invite must not look like a
    // failed family.
    FamilyInviteEntity? invite;
    try {
      invite = await _repository.createInvite();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _created = true;
      _invite = invite;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_created);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_created ? _name.text.trim() : s.familyCreateTitle),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dimens.spacing20),
            child: _created ? _success(context) : _form(context),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.familyCreateHeading, style: text.headlineSmall),
        const SizedBox(height: Dimens.spacing8),
        Text(
          s.familyCreateBody,
          style: text.bodyMedium?.copyWith(color: paletteOf(context).textMuted),
        ),
        const SizedBox(height: Dimens.spacing24),
        Semantics(
          identifier: 'family-create-name',
          child: TextField(
            controller: _name,
            enabled: !_busy,
            autofocus: true,
            maxLength: _maxNameLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: s.familyNameLabel,
              errorText: _error,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: Dimens.spacing16),
        Semantics(
          identifier: 'family-create-submit',
          child: FilledButton(
            onPressed: _busy ? null : _create,
            child: BusyLabel(busy: _busy, label: s.familyCreateAction),
          ),
        ),
      ],
    );
  }

  Widget _success(BuildContext context) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final invite = _invite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, color: accent, size: 32),
          ),
        ),
        const SizedBox(height: Dimens.spacing16),
        Text(
          s.familyCreatedTitle,
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: Dimens.spacing16),
        if (invite != null)
          InviteCodeCard(code: invite.code, caption: s.familyInviteExpiryNote)
        else
          Text(
            s.familyInviteNotCreated,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: paletteOf(context).textMuted,
            ),
          ),
        const SizedBox(height: Dimens.spacing16),
        Semantics(
          identifier: 'family-create-done',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.familyDoneAction),
          ),
        ),
      ],
    );
  }
}
