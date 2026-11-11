import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';
import 'package:opennutritracker/features/family/domain/family_invite_link.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AppPalette paletteOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppPalette.dark
    : AppPalette.light;

/// What to tell the person when a family or sign-in call failed. A server that
/// could not be reached and a code this build does not know both read as the
/// network sentence: nothing the person can do differs.
String familyErrorText(S s, Object error) {
  if (error is FamilyException) {
    return switch (error.error) {
      FamilyError.inviteNotFound => s.familyErrorInviteNotFound,
      FamilyError.inviteExpired => s.familyErrorInviteExpired,
      FamilyError.inviteUsed => s.familyErrorInviteUsed,
      FamilyError.tooManyInvites => s.familyErrorTooManyInvites,
      FamilyError.notOwner => s.familyErrorNotOwner,
      FamilyError.invalidName => s.familyErrorInvalidName,
      FamilyError.notAuthenticated => s.familyErrorNotAuthenticated,
      FamilyError.ownerMustTransfer => s.familyOwnerMustTransfer,
      _ => s.familyNetworkError,
    };
  }
  if (error is AuthException) return s.familyNetworkError;
  return s.familyNetworkError;
}

/// `K7M29QXA` as `K7M2 9QXA`, easier to read out and to type.
String formatInviteCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

/// The invite as text to send. The web build can link straight to the app;
/// the mobile apps have no address to link to, so they send the code.
String inviteShareText(S s, String code) => kIsWeb
    ? s.familyInviteShareLinkText(
        FamilyInviteLink.build(Uri.base, code).toString(),
      )
    : s.familyInviteShareCodeText(formatInviteCode(code));

/// Opens the share sheet with the invite. [context] is the share button's, so
/// iPad can anchor the sheet to it.
void shareInvite(BuildContext context, String code) {
  final box = context.findRenderObject() as RenderBox?;
  SharePlus.instance.share(
    ShareParams(
      text: inviteShareText(S.of(context), code),
      sharePositionOrigin: box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// The text of a message to the person, for a snackbar.
void showFamilyMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A round avatar with the person's initial, tinted from the fixed palette so
/// the same person keeps one colour across the screen.
class FamilyAvatar extends StatelessWidget {
  final String name;
  final int colorIndex;
  final double size;

  const FamilyAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final colors = [
      palette.accent,
      palette.carbs,
      palette.fat,
      palette.protein,
    ];
    final color = colors[colorIndex % colors.length];
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The invite code, big, with copy and share. [caption] says how long it is
/// good for.
class InviteCodeCard extends StatelessWidget {
  final String code;
  final String caption;

  const InviteCodeCard({super.key, required this.code, required this.caption});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) {
      showFamilyMessage(context, S.of(context).familyCodeCopied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final palette = paletteOf(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(Dimens.spacing16),
          child: Column(
            children: [
              Text(
                s.familyInviteCodeTitle,
                style: text.bodySmall?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Dimens.spacing8),
              Semantics(
                identifier: 'family-invite-code',
                child: SelectableText(
                  formatInviteCode(code),
                  style: text.headlineSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: Dimens.spacing8),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimens.spacing12),
        Semantics(
          identifier: 'family-invite-share',
          child: Builder(
            builder: (buttonContext) => FilledButton.icon(
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(s.familyShareAction),
              onPressed: () => shareInvite(buttonContext, code),
            ),
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'family-invite-copy',
          child: OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: Text(s.familyCopyCodeAction),
            onPressed: () => _copy(context),
          ),
        ),
      ],
    );
  }
}

/// A button's label, or a spinner and [busyLabel] while the call runs.
class BusyLabel extends StatelessWidget {
  final bool busy;
  final String label;

  const BusyLabel({super.key, required this.busy, required this.label});

  @override
  Widget build(BuildContext context) {
    if (!busy) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: Dimens.spacing12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
