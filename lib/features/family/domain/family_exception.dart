/// Why a family RPC refused. Each value matches the message the database
/// raises (supabase/migrations/20261106120000_family.sql), so the UI can show
/// a sentence instead of the raw code.
enum FamilyError {
  notAuthenticated('not_authenticated'),
  invalidName('invalid_name'),
  alreadyInFamily('already_in_family'),
  notInFamily('not_in_family'),
  notOwner('not_owner'),
  notAMember('not_a_member'),
  inviteNotFound('invite_not_found'),
  inviteExpired('invite_expired'),
  inviteUsed('invite_used'),
  ownerMustTransfer('owner_must_transfer'),
  tooManyInvites('too_many_invites'),

  /// Anything else: the network, the server, or a code this build does not
  /// know yet.
  unknown('');

  final String code;

  const FamilyError(this.code);

  static FamilyError fromMessage(String message) {
    for (final error in values) {
      if (error != unknown && message == error.code) return error;
    }
    return unknown;
  }
}

class FamilyException implements Exception {
  final FamilyError error;

  /// The underlying error, kept for logs when [error] is
  /// [FamilyError.unknown].
  final Object? cause;

  const FamilyException(this.error, [this.cause]);

  @override
  String toString() => 'FamilyException(${error.name}, $cause)';
}
