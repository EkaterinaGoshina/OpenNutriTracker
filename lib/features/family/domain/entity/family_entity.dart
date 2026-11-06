import 'package:equatable/equatable.dart';

enum FamilyRoleEntity { owner, member }

class FamilyMemberEntity extends Equatable {
  final String userId;
  final String displayName;
  final FamilyRoleEntity role;
  final DateTime joinedAt;

  const FamilyMemberEntity({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  bool get isOwner => role == FamilyRoleEntity.owner;

  @override
  List<Object?> get props => [userId, displayName, role, joinedAt];
}

/// The signed-in user's family as RLS lets them see it: the family itself and
/// everyone in it, oldest member first.
class FamilyEntity extends Equatable {
  final String id;
  final String name;
  final List<FamilyMemberEntity> members;

  const FamilyEntity({
    required this.id,
    required this.name,
    required this.members,
  });

  FamilyMemberEntity? memberOf(String userId) {
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    return null;
  }

  @override
  List<Object?> get props => [id, name, members];
}

class FamilyInviteEntity extends Equatable {
  final String code;
  final DateTime expiresAt;

  const FamilyInviteEntity({required this.code, required this.expiresAt});

  @override
  List<Object?> get props => [code, expiresAt];
}
