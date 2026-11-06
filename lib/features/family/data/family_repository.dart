import 'package:logging/logging.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Families on our Supabase project. Membership changes go through the
/// project's RPCs, which check every rule server-side; reads go through the
/// tables, where RLS limits the caller to their own family.
///
/// Every failure surfaces as a [FamilyException].
class FamilyRepository {
  final _log = Logger('FamilyRepository');
  final SupabaseClient _client;

  FamilyRepository(this._client);

  /// The caller's family, or null when they are in none.
  Future<FamilyEntity?> getMyFamily() => _guard(() async {
    final families = await _client.from('families').select('id, name');
    if (families.isEmpty) return null;
    final family = families.single;
    final familyId = family['id'] as String;

    final members = await _client
        .from('family_members')
        .select('user_id, role, joined_at')
        .eq('family_id', familyId)
        .order('joined_at', ascending: true)
        .order('user_id', ascending: true);
    // No foreign key ties members to profiles (both point at auth.users),
    // so the names come in a second query. RLS already limits profiles to
    // this family plus the caller.
    final profiles = await _client
        .from('profiles')
        .select('user_id, display_name');
    final names = {
      for (final p in profiles)
        p['user_id'] as String: p['display_name'] as String,
    };

    return FamilyEntity(
      id: familyId,
      name: family['name'] as String,
      members: [
        for (final m in members)
          FamilyMemberEntity(
            userId: m['user_id'] as String,
            displayName: names[m['user_id']] ?? '',
            role: m['role'] == 'owner'
                ? FamilyRoleEntity.owner
                : FamilyRoleEntity.member,
            joinedAt: DateTime.parse(m['joined_at'] as String),
          ),
      ],
    );
  });

  Future<String> createFamily(String name) => _guard(
    () async =>
        await _client.rpc<String>('create_family', params: {'p_name': name}),
  );

  Future<FamilyInviteEntity> createInvite() => _guard(() async {
    final rows = await _client.rpc<List<dynamic>>('create_invite');
    return _invite(rows.single as Map<String, dynamic>);
  });

  /// Invites nobody has used yet and that have not expired. Owner only; a
  /// member gets an empty list from RLS.
  Future<List<FamilyInviteEntity>> getPendingInvites() => _guard(() async {
    final rows = await _client
        .from('family_invites')
        .select('code, expires_at')
        .isFilter('used_by', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('expires_at', ascending: true);
    return rows.map(_invite).toList();
  });

  Future<void> revokeInvite(String code) => _guard(
    () async => await _client.from('family_invites').delete().eq('code', code),
  );

  /// Returns the id of the family joined. Joining the caller's own family
  /// again is not an error.
  Future<String> joinFamily(String code) => _guard(
    () async =>
        await _client.rpc<String>('join_family', params: {'p_code': code}),
  );

  Future<void> leaveFamily() =>
      _guard(() async => await _client.rpc<void>('leave_family'));

  Future<void> removeMember(String userId) => _guard(
    () async =>
        await _client.rpc<void>('remove_member', params: {'p_user_id': userId}),
  );

  Future<void> transferOwnership(String userId) => _guard(
    () async => await _client.rpc<void>(
      'transfer_ownership',
      params: {'p_user_id': userId},
    ),
  );

  /// Owner only. A member's update matches no row under RLS, which is
  /// reported as [FamilyError.notOwner].
  Future<void> renameFamily(String familyId, String name) => _guard(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw const FamilyException(FamilyError.invalidName);
    }
    final updated = await _client
        .from('families')
        .update({'name': trimmed})
        .eq('id', familyId)
        .select('id');
    if (updated.isEmpty) throw const FamilyException(FamilyError.notOwner);
  });

  Future<void> setDisplayName(String userId, String name) => _guard(() async {
    final trimmed = name.trim();
    if (trimmed.length > 60) {
      throw const FamilyException(FamilyError.invalidName);
    }
    await _client
        .from('profiles')
        .update({'display_name': trimmed})
        .eq('user_id', userId);
  });

  static FamilyInviteEntity _invite(Map<String, dynamic> row) =>
      FamilyInviteEntity(
        code: row['code'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FamilyException {
      rethrow;
    } on PostgrestException catch (e) {
      final error = FamilyError.fromMessage(e.message);
      if (error == FamilyError.unknown) {
        _log.warning('Family request failed', e);
      }
      throw FamilyException(error, e);
    } catch (e) {
      _log.warning('Family request failed', e);
      throw FamilyException(FamilyError.unknown, e);
    }
  }
}
