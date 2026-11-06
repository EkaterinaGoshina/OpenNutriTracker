import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/family/domain/family_invite_link.dart';
import 'package:opennutritracker/features/family/domain/pending_family_invite.dart';

void main() {
  group('normalize', () {
    test('accepts a code typed loosely', () {
      expect(FamilyInviteLink.normalize(' k7qm-2xpa '), 'K7QM2XPA');
      expect(FamilyInviteLink.normalize('K7QM 2XPA'), 'K7QM2XPA');
    });

    test('rejects what cannot be a code', () {
      expect(FamilyInviteLink.normalize(null), isNull);
      expect(FamilyInviteLink.normalize(''), isNull);
      expect(FamilyInviteLink.normalize('K7QM2XP'), isNull);
      expect(FamilyInviteLink.normalize('K7QM2XPAB'), isNull);
      // I, O, 0 and 1 are not in the alphabet.
      expect(FamilyInviteLink.normalize('K7QM2XPO'), isNull);
      expect(FamilyInviteLink.normalize('K7QM2XP1'), isNull);
    });
  });

  test('reads the code from a launch address', () {
    expect(
      FamilyInviteLink.codeFrom(
        Uri.parse('https://app.example.com/?join=k7qm-2xpa#/'),
      ),
      'K7QM2XPA',
    );
    expect(
      FamilyInviteLink.codeFrom(Uri.parse('https://app.example.com/#/')),
      isNull,
    );
  });

  test('builds a link to the start screen', () {
    final link = FamilyInviteLink.build(
      Uri.parse('https://app.example.com/?lang=ru#/profile'),
      'K7QM2XPA',
    );
    expect(link.toString(), 'https://app.example.com/?lang=ru&join=K7QM2XPA');
  });

  test('strips the code and keeps the route', () {
    expect(
      FamilyInviteLink.strip(
        Uri.parse('https://app.example.com/?join=K7QM2XPA#/home'),
      ).toString(),
      'https://app.example.com/#/home',
    );
    expect(
      FamilyInviteLink.strip(
        Uri.parse('http://localhost:8080/?code=abc&join=K7QM2XPA'),
      ).toString(),
      'http://localhost:8080/?code=abc',
    );
  });

  test('pending invite holds the launch code until cleared', () {
    final pending = PendingFamilyInvite(
      Uri.parse('https://app.example.com/?join=K7QM2XPA'),
    );
    expect(pending.code, 'K7QM2XPA');
    pending.clear();
    expect(pending.code, isNull);
    expect(PendingFamilyInvite(Uri.parse('file:///app')).code, isNull);
  });
}
