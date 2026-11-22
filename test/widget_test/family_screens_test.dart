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
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final entered = <String>[];
  AuthException? failure;

  @override
  Future<User?> enter(String name, String password) async {
    entered.add(name);
    if (failure != null) throw failure!;
    return null;
  }

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
    Future<void> fill(WidgetTester tester, String name, String password) async {
      await tester.enterText(find.byType(TextField).at(0), name);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
    }

    testWidgets('an empty name is refused without a request', (tester) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, '   ', '');
      expect(find.text(l10nEn.familyNameEmpty), findsOneWidget);
      expect(account.entered, isEmpty);
    });

    testWidgets('a Cyrillic name and a short password go through', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, 'Катя', 'к');
      expect(account.entered, ['Катя']);
      expect(find.text(l10nEn.familyNameEmpty), findsNothing);
    });

    testWidgets('an empty password goes through', (tester) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, 'катя', '');
      expect(account.entered, ['катя']);
    });

    testWidgets('a taken name with another password says so', (tester) async {
      account.failure = const AuthException(
        'Wrong password',
        code: 'wrong_password',
      );
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, 'катя', 'x');
      expect(find.text(l10nEn.familyWrongPassword), findsOneWidget);
    });
  });

  group('SignInScreen on the first run', () {
    testWidgets('can be skipped with Later', (tester) async {
      var done = 0;
      await tester.pumpWidget(_app(SignInScreen(onDone: (_) => done++)));
      expect(find.text(l10nEn.familyFirstRunNote), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.text(l10nEn.familyLaterAction));
      await tester.pump();
      expect(done, 1);
      expect(account.entered, isEmpty);
    });

    testWidgets('signing in moves on to onboarding', (tester) async {
      var done = 0;
      await tester.pumpWidget(_app(SignInScreen(onDone: (_) => done++)));
      await tester.enterText(find.byType(TextField).at(0), 'Катя');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(account.entered, ['Катя']);
      expect(done, 1);
    });
  });

  group('AccountRepository names', () {
    test('a name maps to one address whatever its case and spaces', () {
      final email = AccountRepository.emailForName(' Катя ');
      expect(email, AccountRepository.emailForName('катя'));
      expect(email, endsWith('@${AccountRepository.loginDomain}'));
      final local = email.split('@').first;
      expect(local.length, lessThanOrEqualTo(64));
      expect(RegExp(r'^[a-z0-9-]+$').hasMatch(local), isTrue);
    });

    test('the address of a name account shows as the name', () {
      for (final name in ['катя', 'anna', 'мама 2', 'ёжик-😀']) {
        expect(
          AccountRepository.displayName(AccountRepository.emailForName(name)),
          name,
        );
      }
      expect(AccountRepository.displayName('anna@gmail.com'), 'anna@gmail.com');
    });

    test('the longest allowed name still fits an address', () {
      final name = 'я' * AccountRepository.maxNameLength;
      expect(AccountRepository.isNameTooLong(name), isFalse);
      final local = AccountRepository.emailForName(name).split('@').first;
      expect(local.length, lessThanOrEqualTo(64));
      expect(
        AccountRepository.isNameTooLong(
          'я' * (AccountRepository.maxNameLength + 1),
        ),
        isTrue,
      );
    });

    test('any password, even an empty one, is long enough for Supabase', () {
      expect(AccountRepository.passwordFor('').length, greaterThanOrEqualTo(6));
    });
  });
}
