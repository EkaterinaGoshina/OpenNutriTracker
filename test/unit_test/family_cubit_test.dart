import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';
import 'package:opennutritracker/features/family/presentation/bloc/family_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAccount implements AccountRepository {
  @override
  User? currentUser;

  final changes = StreamController<User?>.broadcast();
  var signedOut = 0;

  _FakeAccount(this.currentUser);

  @override
  Stream<User?> get userChanges => changes.stream;

  @override
  Future<void> signOut() async {
    signedOut++;
    currentUser = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilies implements FamilyRepository {
  FamilyEntity? family;
  var invites = <FamilyInviteEntity>[];
  FamilyException? failure;
  final calls = <String>[];

  @override
  Future<FamilyEntity?> getMyFamily() async {
    calls.add('getMyFamily');
    if (failure != null) throw failure!;
    return family;
  }

  @override
  Future<List<FamilyInviteEntity>> getPendingInvites() async {
    calls.add('getPendingInvites');
    return invites;
  }

  @override
  Future<void> leaveFamily() async {
    calls.add('leaveFamily');
    family = null;
  }

  @override
  Future<FamilyInviteEntity> createInvite() async {
    calls.add('createInvite');
    final invite = FamilyInviteEntity(
      code: 'K7M29QXA',
      expiresAt: DateTime.utc(2030),
    );
    invites = [...invites, invite];
    return invite;
  }

  FamilyException? revokeFailure;

  @override
  Future<void> revokeInvite(String code) async {
    if (revokeFailure != null) throw revokeFailure!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026).toIso8601String(),
  email: '$id@example.com',
);

FamilyEntity _family(String ownerId, [String? memberId]) => FamilyEntity(
  id: 'f1',
  name: 'Ивановы',
  members: [
    FamilyMemberEntity(
      userId: ownerId,
      displayName: 'Катя',
      role: FamilyRoleEntity.owner,
      joinedAt: DateTime.utc(2026),
    ),
    if (memberId != null)
      FamilyMemberEntity(
        userId: memberId,
        displayName: 'Аня',
        role: FamilyRoleEntity.member,
        joinedAt: DateTime.utc(2026, 2),
      ),
  ],
);

void main() {
  late _FakeFamilies families;

  setUp(() => families = _FakeFamilies());

  test('signed out: loaded, no family, nothing requested', () async {
    final cubit = FamilyCubit(_FakeAccount(null), families);
    await cubit.load();
    expect(cubit.state.status, FamilyLoadStatus.loaded);
    expect(cubit.state.signedIn, isFalse);
    expect(cubit.state.family, isNull);
    expect(families.calls, isEmpty);
    await cubit.close();
  });

  test('a restored session is known before the family is read', () {
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    expect(cubit.state.status, FamilyLoadStatus.loading);
    expect(cubit.state.signedIn, isTrue);
    cubit.close();
  });

  test('owner: family and pending invites are read', () async {
    families
      ..family = _family('u1', 'u2')
      ..invites = [
        FamilyInviteEntity(code: 'AAAAAAAA', expiresAt: DateTime.utc(2030)),
      ];
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    await cubit.load();
    expect(cubit.state.isOwner, isTrue);
    expect(cubit.state.family!.members, hasLength(2));
    expect(cubit.state.invites, hasLength(1));
    await cubit.close();
  });

  test('member: invites are not requested', () async {
    families.family = _family('u1', 'u2');
    final cubit = FamilyCubit(_FakeAccount(_user('u2')), families);
    await cubit.load();
    expect(cubit.state.isOwner, isFalse);
    expect(cubit.state.invites, isEmpty);
    expect(families.calls, ['getMyFamily']);
    await cubit.close();
  });

  test('signed in without a family', () async {
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    await cubit.load();
    expect(cubit.state.status, FamilyLoadStatus.loaded);
    expect(cubit.state.signedIn, isTrue);
    expect(cubit.state.family, isNull);
    await cubit.close();
  });

  test('a failed read is a failure state, not a crash', () async {
    families.failure = const FamilyException(FamilyError.unknown);
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    await cubit.load();
    expect(cubit.state.status, FamilyLoadStatus.failure);
    expect(cubit.state.signedIn, isTrue);
    await cubit.close();
  });

  test('leaving reads the family again', () async {
    families.family = _family('u1');
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    await cubit.load();
    await cubit.leave();
    expect(cubit.state.family, isNull);
    expect(families.calls, contains('leaveFamily'));
    await cubit.close();
  });

  test('a new invite shows up in the list', () async {
    families.family = _family('u1');
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    await cubit.load();
    await cubit.createInvite();
    expect(cubit.state.invites.single.code, 'K7M29QXA');
    await cubit.close();
  });

  test('a refused change reaches the caller and keeps the state', () async {
    families.family = _family('u1');
    final cubit = FamilyCubit(_FakeAccount(_user('u1')), families);
    await cubit.load();
    families.revokeFailure = const FamilyException(FamilyError.notOwner);
    await expectLater(
      cubit.revokeInvite('AAAAAAAA'),
      throwsA(isA<FamilyException>()),
    );
    expect(cubit.state.status, FamilyLoadStatus.loaded);
    expect(cubit.state.family, isNotNull);
    await cubit.close();
  });

  test('signing out clears the family', () async {
    families.family = _family('u1');
    final account = _FakeAccount(_user('u1'));
    final cubit = FamilyCubit(account, families);
    await cubit.load();
    await cubit.signOut();
    expect(account.signedOut, 1);
    expect(cubit.state.signedIn, isFalse);
    expect(cubit.state.family, isNull);
    await cubit.close();
  });
}
