import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/presentation/widgets/error_dialog.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/presentation/bloc/family_cubit.dart';
import 'package:opennutritracker/features/family/presentation/screens/create_family_screen.dart';
import 'package:opennutritracker/features/family/presentation/screens/join_family_screen.dart';
import 'package:opennutritracker/features/family/presentation/screens/sign_in_screen.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The family: an invitation to start or join one while there is none, and
/// the members, invite codes and ways to leave once there is.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late final FamilyCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = locator<FamilyCubit>()..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  /// Runs a change to the family and puts a failure into words.
  Future<void> _run(Future<void> Function() action) async {
    final s = S.of(context);
    try {
      await action();
    } catch (e) {
      if (mounted) showFamilyMessage(context, familyErrorText(s, e));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final s = S.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Sends the person through sign-in first if they have no account, then on
  /// to [next]. Whatever [next] does, the family is read again afterwards.
  Future<void> _startWith(Widget next) async {
    if (!_cubit.state.signedIn) {
      final signedIn = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
      if (signedIn != true || !mounted) return;
    }
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => next));
    if (mounted) _cubit.load();
  }

  Future<void> _leave(FamilyState state) async {
    final s = S.of(context);
    final family = state.family!;
    final onlyMember = family.members.length == 1;
    if (state.isOwner && !onlyMember) {
      showFamilyMessage(context, s.familyOwnerMustTransfer);
      return;
    }
    final confirmed = await _confirm(
      title: onlyMember ? s.familyDeleteTitle : s.familyLeaveTitle,
      body: onlyMember ? s.familyDeleteBody : s.familyLeaveBody,
      confirmLabel: onlyMember ? s.familyDeleteConfirm : s.familyLeaveConfirm,
    );
    if (confirmed) await _run(_cubit.leave);
  }

  Future<void> _memberMenu(FamilyMemberEntity member) async {
    final s = S.of(context);
    final name = _nameOf(s, member);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: FamilyAvatar(name: name, colorIndex: 0),
              title: Text(name, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Semantics(
              identifier: 'family-member-make-owner',
              child: ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(s.familyMakeOwnerAction),
                onTap: () => Navigator.of(ctx).pop('owner'),
              ),
            ),
            Semantics(
              identifier: 'family-member-remove',
              child: ListTile(
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  s.familyRemoveMemberAction,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'owner') {
      final ok = await _confirm(
        title: s.familyMakeOwnerTitle(name),
        body: s.familyMakeOwnerBody,
        confirmLabel: s.familyMakeOwnerAction,
      );
      if (ok) await _run(() => _cubit.transferOwnership(member.userId));
    } else {
      final ok = await _confirm(
        title: s.familyRemoveMemberTitle(name),
        body: s.familyRemoveMemberBody,
        confirmLabel: s.familyRemoveMemberConfirm,
      );
      if (ok) await _run(() => _cubit.removeMember(member.userId));
    }
  }

  String _nameOf(S s, FamilyMemberEntity member) =>
      member.displayName.trim().isEmpty
      ? s.familyMemberUnnamed
      : member.displayName.trim();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return BlocBuilder<FamilyCubit, FamilyState>(
      bloc: _cubit,
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(s.familyTitle),
          actions: [
            if (state.signedIn)
              PopupMenuButton<String>(
                onSelected: (_) => _cubit.signOut(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'sign-out',
                    child: Text(s.familySignOutAction),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: switch (state.status) {
            FamilyLoadStatus.loading => const _Skeleton(),
            FamilyLoadStatus.failure => SingleChildScrollView(
              child: Center(
                child: ErrorDialog(
                  errorText: s.familyLoadError,
                  onRefreshPressed: _cubit.load,
                  retryIdentifier: 'family-retry',
                ),
              ),
            ),
            FamilyLoadStatus.loaded =>
              state.family == null
                  ? _intro(context, state)
                  : _family(context, state),
          },
        ),
      ),
    );
  }

  Widget _intro(BuildContext context, FamilyState state) {
    final s = S.of(context);
    final muted = paletteOf(context).textMuted;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Dimens.spacing20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmptyHint(
              icon: Icons.groups_rounded,
              title: s.familyIntroTitle,
              subtitle: s.familyIntroBody,
            ),
            const SizedBox(height: Dimens.spacing8),
            Semantics(
              identifier: 'family-intro-create',
              child: FilledButton(
                onPressed: () => _startWith(const CreateFamilyScreen()),
                child: Text(s.familyCreateAction),
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'family-intro-join',
              child: OutlinedButton(
                onPressed: () => _startWith(const JoinFamilyScreen()),
                child: Text(s.familyHaveCodeAction),
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Text(
              state.signedIn && state.email != null
                  ? s.familySignedInAs(state.email!)
                  : s.familyAccountNote,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _family(BuildContext context, FamilyState state) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    final family = state.family!;
    return RefreshIndicator(
      onRefresh: _cubit.load,
      child: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          Text(family.name, style: text.headlineSmall),
          Text(
            s.familyMembersCount(family.members.length),
            style: text.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: Dimens.spacing16),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
            child: Column(
              children: [
                for (var i = 0; i < family.members.length; i++)
                  _memberRow(context, state, family.members[i], i),
              ],
            ),
          ),
          if (state.isOwner) ...[
            const SizedBox(height: Dimens.spacing16),
            for (final invite in state.invites) ...[
              _inviteCard(context, invite),
              const SizedBox(height: Dimens.spacing12),
            ],
            Semantics(
              identifier: 'family-new-invite',
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(s.familyNewInviteAction),
                onPressed: () => _run(_cubit.createInvite),
              ),
            ),
          ] else ...[
            const SizedBox(height: Dimens.spacing12),
            Text(
              s.familyOnlyOwnerNote,
              style: text.bodySmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: Dimens.spacing24),
          Semantics(
            identifier: 'family-leave',
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _leave(state),
              child: Text(s.familyLeaveAction),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(
    BuildContext context,
    FamilyState state,
    FamilyMemberEntity member,
    int index,
  ) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final name = _nameOf(s, member);
    final isMe = member.userId == state.userId;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: index == 0
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: paletteOf(context).border)),
            ),
      child: Row(
        children: [
          FamilyAvatar(name: name, colorIndex: index),
          const SizedBox(width: Dimens.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name ${s.familyYouSuffix}' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (member.isOwner)
                  Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_outlined,
                        size: 14,
                        color: accent,
                      ),
                      const SizedBox(width: Dimens.spacing4),
                      Text(
                        s.familyOwnerBadge,
                        style: text.bodySmall?.copyWith(color: accent),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (state.isOwner && !isMe)
            Semantics(
              identifier: 'family-member-menu',
              child: IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _memberMenu(member),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inviteCard(BuildContext context, FamilyInviteEntity invite) {
    final s = S.of(context);
    final text = Theme.of(context).textTheme;
    final remaining = invite.expiresAt.difference(DateTime.now());
    final hours = remaining.inMinutes <= 0
        ? 1
        : (remaining.inMinutes / 60).ceil();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing4,
        Dimens.spacing8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.familyInviteCodeTitle,
                  style: text.bodySmall?.copyWith(
                    color: paletteOf(context).textMuted,
                  ),
                ),
                Text(
                  formatInviteCode(invite.code),
                  style: text.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  s.familyInviteHoursLeft(hours),
                  style: text.bodySmall?.copyWith(
                    color: paletteOf(context).textMuted,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            identifier: 'family-invite-share-row',
            child: Builder(
              builder: (buttonContext) => IconButton(
                tooltip: s.familyShareAction,
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => shareInvite(buttonContext, invite.code),
              ),
            ),
          ),
          Semantics(
            identifier: 'family-invite-revoke',
            child: IconButton(
              tooltip: s.familyRevokeInviteTooltip,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _run(() => _cubit.revokeInvite(invite.code)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final fill = paletteOf(context).surfaceMuted;
    Widget bar(double width, double height, {double radius = 8}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return Semantics(
      label: S.of(context).familyTitle,
      child: Padding(
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(180, 24),
            const SizedBox(height: Dimens.spacing8),
            bar(90, 14),
            const SizedBox(height: Dimens.spacing16),
            AppCard(
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: Dimens.spacing8,
                      ),
                      child: Row(
                        children: [
                          bar(40, 40, radius: 20),
                          const SizedBox(width: Dimens.spacing12),
                          bar(120, 14),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
