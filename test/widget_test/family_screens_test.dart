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
  final signedIn = <String>[];
  final signedUp = <String>[];
  AuthException? failure;

  @override
  Future<User?> signIn(String login, String password) async {
    signedIn.add(login);
    if (failure != null) throw failure!;
    return null;
  }

  @override
  Future<User?> signUp(String login, String password) async {
    signedUp.add(login);
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
    Future<void> fill(
      WidgetTester tester,
      String login,
      String password,
    ) async {
      await tester.enterText(find.byType(TextField).at(0), login);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
    }

    testWidgets('a login with an address in it is refused without a request', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, 'anna@mail.com', 'secret1');
      expect(find.text(l10nEn.familyLoginInvalid), findsOneWidget);
      expect(account.signedIn, isEmpty);
    });

    testWidgets('a short password is refused without a request', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, 'anna', '123');
      expect(
        find.text(
          l10nEn.familyPasswordTooShort(AccountRepository.minPasswordLength),
        ),
        findsOneWidget,
      );
      expect(account.signedIn, isEmpty);
    });

    testWidgets('a wrong password says so', (tester) async {
      account.failure = const AuthException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
      await tester.pumpWidget(_app(const SignInScreen()));
      await fill(tester, 'anna', 'secret1');
      expect(account.signedIn, ['anna']);
      expect(find.text(l10nEn.familyWrongCredentials), findsOneWidget);
    });

    testWidgets('creating an account with a taken login says so', (
      tester,
    ) async {
      account.failure = const AuthException(
        'User already registered',
        statusCode: '422',
        code: 'user_already_exists',
      );
      await tester.pumpWidget(_app(const SignInScreen()));
      await tester.tap(find.text(l10nEn.familyToSignUpAction));
      await tester.pump();
      expect(find.text(l10nEn.familySignUpHeading), findsOneWidget);
      await fill(tester, 'Anna', 'secret1');
      expect(account.signedUp, ['Anna']);
      expect(account.signedIn, isEmpty);
      expect(find.text(l10nEn.familyLoginTaken), findsOneWidget);
    });
  });

  group('SignInScreen on the first run', () {
    testWidgets('opens on creating an account and can be skipped', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(_app(SignInScreen(onDone: (_) => done++)));
      expect(find.text(l10nEn.familySignUpHeading), findsOneWidget);
      expect(find.text(l10nEn.familyFirstRunNote), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.text(l10nEn.familyLaterAction));
      await tester.pump();
      expect(done, 1);
      expect(account.signedUp, isEmpty);
    });

    testWidgets('a new account moves on to onboarding', (tester) async {
      var done = 0;
      await tester.pumpWidget(_app(SignInScreen(onDone: (_) => done++)));
      await tester.enterText(find.byType(TextField).at(0), 'anna');
      await tester.enterText(find.byType(TextField).at(1), 'secret1');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(account.signedUp, ['anna']);
      expect(done, 1);
    });
  });

  group('AccountRepository logins', () {
    test('a login maps to one address whatever its case', () {
      expect(
        AccountRepository.emailForLogin(' Anna '),
        'anna@${AccountRepository.loginDomain}',
      );
    });

    test('the address of a login account shows as the login', () {
      expect(
        AccountRepository.displayName(AccountRepository.emailForLogin('anna')),
        'anna',
      );
      expect(AccountRepository.displayName('anna@gmail.com'), 'anna@gmail.com');
    });

    test('only safe characters make a login', () {
      expect(AccountRepository.isValidLogin('anna.k-2_x'), isTrue);
      expect(AccountRepository.isValidLogin('an'), isFalse);
      expect(AccountRepository.isValidLogin('.anna'), isFalse);
      expect(AccountRepository.isValidLogin('анна'), isFalse);
      expect(AccountRepository.isValidLogin('an na'), isFalse);
    });
  });
}
