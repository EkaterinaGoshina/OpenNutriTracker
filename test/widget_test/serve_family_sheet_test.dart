import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/entity/family_portion_entity.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/kitchen_eat_sheet.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Account implements AccountRepository {
  @override
  User? currentUser = User(
    id: 'katya',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Families implements FamilyRepository {
  FamilyEntity? family;
  final served = <List<PortionToServe>>[];
  final attempts = <List<PortionToServe>>[];
  Object? failure;

  @override
  Future<FamilyEntity?> getMyFamily() async => family;

  @override
  Future<int> servePortions(List<PortionToServe> portions) async {
    attempts.add(portions);
    if (failure != null) throw failure!;
    served.add(portions);
    return portions.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bloc implements MealDetailBloc {
  final added = <IntakeEntity>[];

  @override
  Future<void> addIntakeEntity(IntakeEntity intakeEntity) async =>
      added.add(intakeEntity);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home implements HomeBloc {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Diary implements DiaryBloc {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CalendarDay implements CalendarDayBloc {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

FamilyMemberEntity _member(String id, String name, {bool owner = false}) =>
    FamilyMemberEntity(
      userId: id,
      displayName: name,
      role: owner ? FamilyRoleEntity.owner : FamilyRoleEntity.member,
      joinedAt: DateTime.utc(2026),
    );

// 100 kcal per 100 g, so 1 g is 1 kcal.
final _rice = MealEntity(
  code: 'rice',
  name: 'Рис',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 20,
    fat100: 1,
    proteins100: 2,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

Future<void> _open(WidgetTester tester, void Function(bool?) onResult) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        locale: const Locale('ru'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showServeFamilySheet(
                  context,
                  meal: _rice,
                  initialType: IntakeTypeEntity.dinner,
                  day: DateTime(2026, 11, 11, 19),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late _Families families;
  late _Bloc bloc;

  setUp(() async {
    await locator.reset();
    families = _Families()
      ..family = FamilyEntity(
        id: 'f',
        name: 'Титовы',
        members: [
          _member('katya', 'Катя', owner: true),
          _member('boris', 'Борис'),
          _member('masha', 'Маша'),
        ],
      );
    bloc = _Bloc();
    locator
      ..registerSingleton<AccountRepository>(_Account())
      ..registerSingleton<FamilyRepository>(families)
      ..registerSingleton<MealDetailBloc>(bloc)
      ..registerSingleton<HomeBloc>(_Home())
      ..registerSingleton<DiaryBloc>(_Diary())
      ..registerSingleton<CalendarDayBloc>(_CalendarDay());
  });

  tearDown(() => locator.reset());

  testWidgets('a single food is served to the people who got an amount', (
    tester,
  ) async {
    bool? result;
    await _open(tester, (r) => result = r);

    // Opens straight on the family, with a field for each person.
    expect(find.text('Борщ'), findsNothing);
    expect(find.text('Рис'), findsOneWidget);
    expect(find.text('Я'), findsOneWidget);
    expect(find.text('Борис'), findsOneWidget);
    expect(find.text('Маша'), findsOneWidget);
    // Not a dish from the kitchen, so no Себе / На семью switch.
    expect(find.text('Себе'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), '120');
    await tester.enterText(find.byType(TextField).at(1), '80');
    // Маша is left empty on purpose.
    await tester.pump();

    // 120 g + 80 g at 1 kcal per gram.
    expect(find.textContaining('200'), findsWidgets);

    await tester.tap(find.text('Разложить'));
    await tester.pumpAndSettle();

    expect(families.served, hasLength(1));
    final portions = families.served.single;
    expect(portions.map((p) => p.recipientId), ['boris']);
    expect(portions.single.intake.amount, 80);
    expect(portions.single.intake.type, IntakeTypeEntity.dinner);
    expect(portions.single.intake.meal.name, 'Рис');
    // The cook's own portion goes into their own diary, not to the server.
    expect(bloc.added.single.amount, 120);
    expect(bloc.added.single.id, isNot(portions.single.id));
    expect(result, isTrue);
  });

  testWidgets(
    'nothing is logged when the server refuses, and a retry reuses ids',
    (tester) async {
      bool? result;
      families.failure = StateError('offline');
      await _open(tester, (r) => result = r);

      await tester.enterText(find.byType(TextField).at(0), '120');
      await tester.enterText(find.byType(TextField).at(1), '80');
      await tester.pump();
      await tester.tap(find.text('Разложить'));
      await tester.pumpAndSettle();

      expect(bloc.added, isEmpty, reason: 'own portion waits for the server');
      expect(find.textContaining('Ничего не записано'), findsOneWidget);
      expect(result, isNull, reason: 'the sheet stays open for a retry');

      families.failure = null;
      await tester.tap(find.text('Разложить'));
      await tester.pumpAndSettle();
      expect(families.served.single.single.recipientId, 'boris');
      expect(bloc.added.single.amount, 120);
      expect(result, isTrue);
    },
  );

  testWidgets('explains when there is nobody to serve', (tester) async {
    families.family = FamilyEntity(
      id: 'f',
      name: 'Титовы',
      members: [_member('katya', 'Катя', owner: true)],
    );
    await _open(tester, (_) {});

    expect(
      find.textContaining('Войдите в аккаунт и вступите в семью'),
      findsOneWidget,
    );
    final submit = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submit.onPressed, isNull);
  });
}
