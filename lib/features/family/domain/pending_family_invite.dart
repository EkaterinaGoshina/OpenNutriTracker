import 'package:opennutritracker/features/family/domain/family_invite_link.dart';

/// The invite code the app was opened with, held until the user is signed in
/// and the join goes through. Read once at launch: Google's sign-in redirect
/// returns to the same `?join=` address, and email sign-in never leaves the
/// page, so neither loses it.
class PendingFamilyInvite {
  String? _code;

  PendingFamilyInvite(Uri launchUri)
    : _code = FamilyInviteLink.codeFrom(launchUri);

  String? get code => _code;

  void clear() => _code = null;
}
