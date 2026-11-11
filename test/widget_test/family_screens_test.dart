import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/family_exception.dart';
import 'package:opennutritracker/features/family/presentation/screens/join_family_screen.dart';
import 'package:opennutritracker/features/family/presentation/screens/sign_in_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../helpers/test_l10n.dart';

class _FakeFamilies implements FamilyRepository {
  final joined = <String>[];
  FamilyException? failure;

  @override
  Future<String> joinFamily(String code) async {
    joined.add(code);
    if (failure != null) throw failure!;
    return 'f1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccount implements AccountRepository {
  final sentTo = <String>[];

  @override
  bool get supportsGoogle => false;

  @override
  Future<void> sendEmailCode(String email) async => sentTo.add(email);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: home,
);

void main() {
  late _FakeFamilies families;
  late _FakeAccount account;

  setUp(() async {
    await locator.reset();
    families = _FakeFamilies();
    account = _FakeAccount();
    locator
      ..registerSingleton<FamilyRepository>(families)
      ..registerSingleton<AccountRepository>(account);
  });

  tearDown(() => locator.reset());

  group('JoinFamilyScreen', () {
    testWidgets('a code of the wrong shape is refused without a request', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const JoinFamilyScreen()));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text(l10nEn.familyErrorInviteNotFound), findsOneWidget);
      expect(families.joined, isEmpty);
    });

    testWidgets('a typed code is normalised and sent', (tester) async {
      await tester.pumpWidget(_app(const JoinFamilyScreen()));
      await tester.enterText(find.byType(TextField), 'k7m2-9qxa');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(families.joined, ['K7M29QXA']);
    });

    testWidgets('an expired code is explained under the field', (tester) async {
      families.failure = const FamilyException(FamilyError.inviteExpired);
      await tester.pumpWidget(_app(const JoinFamilyScreen()));
      await tester.enterText(find.byType(TextField), 'K7M29QXA');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.familyErrorInviteExpired), findsOneWidget);
    });

    testWidgets('being in a family already gets its own card', (tester) async {
      families.failure = const FamilyException(FamilyError.alreadyInFamily);
      await tester.pumpWidget(_app(const JoinFamilyScreen()));
      await tester.enterText(find.byType(TextField), 'K7M29QXA');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.familyAlreadyInFamilyTitle), findsOneWidget);
      expect(find.text(l10nEn.familyOpenMyFamilyAction), findsOneWidget);
    });
  });

  group('SignInScreen', () {
    testWidgets('an address that is not one is refused without a request', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await tester.enterText(find.byType(TextField), 'anna');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text(l10nEn.familyEmailInvalid), findsOneWidget);
      expect(account.sentTo, isEmpty);
    });

    testWidgets('after the code is sent, the code step shows the address', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await tester.enterText(find.byType(TextField), 'anna@mail.com');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(account.sentTo, ['anna@mail.com']);
      expect(
        find.text(l10nEn.familyCodeSentTo('anna@mail.com')),
        findsOneWidget,
      );
      expect(find.text(l10nEn.familyResendIn('1:00')), findsOneWidget);
      // Let the resend timer finish so the test leaves nothing running.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
