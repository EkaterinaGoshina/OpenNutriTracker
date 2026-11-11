import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';

enum FamilyLoadStatus { loading, loaded, failure }

class FamilyState extends Equatable {
  final FamilyLoadStatus status;

  /// The signed-in account, or null when there is none.
  final String? userId;
  final String? email;

  /// The account's family; null when signed out or in none.
  final FamilyEntity? family;

  /// Codes nobody has used yet. Filled for the owner only.
  final List<FamilyInviteEntity> invites;

  const FamilyState({
    required this.status,
    this.userId,
    this.email,
    this.family,
    this.invites = const [],
  });

  bool get signedIn => userId != null;

  bool get isOwner =>
      userId != null && (family?.memberOf(userId!)?.isOwner ?? false);

  @override
  List<Object?> get props => [status, userId, email, family, invites];
}

/// The signed-in account and its family, as the family screen and the kitchen
/// card show them. Mutations call the repository and then read the family
/// again, so what is on screen is what the server says. Failures are rethrown
/// as [FamilyException] for the screen to put into words.
class FamilyCubit extends Cubit<FamilyState> {
  final AccountRepository _account;
  final FamilyRepository _family;
  StreamSubscription<Object?>? _userSub;

  FamilyCubit(this._account, this._family)
    : super(
        FamilyState(
          // A restored session is known at once, so the kitchen card can show
          // a placeholder only for people who have an account.
          status: FamilyLoadStatus.loading,
          userId: _account.currentUser?.id,
          email: _account.currentUser?.email,
        ),
      ) {
    _userSub = _account.userChanges.listen((_) => load());
  }

  Future<void> load() async {
    final user = _account.currentUser;
    if (user == null) {
      emit(const FamilyState(status: FamilyLoadStatus.loaded));
      return;
    }
    // Keep what is on screen while it is read again; only the first read
    // shows the placeholder.
    if (state.userId != user.id) {
      emit(
        FamilyState(
          status: FamilyLoadStatus.loading,
          userId: user.id,
          email: user.email,
        ),
      );
    }
    try {
      final family = await _family.getMyFamily();
      final isOwner = family?.memberOf(user.id)?.isOwner ?? false;
      final invites = isOwner
          ? await _family.getPendingInvites()
          : const <FamilyInviteEntity>[];
      if (isClosed) return;
      emit(
        FamilyState(
          status: FamilyLoadStatus.loaded,
          userId: user.id,
          email: user.email,
          family: family,
          invites: invites,
        ),
      );
    } on FamilyException {
      if (isClosed) return;
      emit(
        FamilyState(
          status: FamilyLoadStatus.failure,
          userId: user.id,
          email: user.email,
        ),
      );
    }
  }

  Future<void> createInvite() => _then(_family.createInvite);

  Future<void> revokeInvite(String code) =>
      _then(() => _family.revokeInvite(code));

  Future<void> leave() => _then(_family.leaveFamily);

  Future<void> removeMember(String userId) =>
      _then(() => _family.removeMember(userId));

  Future<void> transferOwnership(String userId) =>
      _then(() => _family.transferOwnership(userId));

  Future<void> signOut() async {
    await _account.signOut();
    await load();
  }

  Future<void> _then(Future<Object?> Function() action) async {
    await action();
    await load();
  }

  @override
  Future<void> close() {
    _userSub?.cancel();
    return super.close();
  }
}
