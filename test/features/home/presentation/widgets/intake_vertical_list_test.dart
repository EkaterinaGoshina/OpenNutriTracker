import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_card.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_sort_type.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/core/utils/vertical_list_popup_menu_selections.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/intake_vertical_list.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import '../../../../helpers/test_l10n.dart';

/// What a drag between meals did, in order (#1317 review).
final _dropLog = <String>[];

/// Holds the add of a drag open, as a slow write would.
Completer<void>? _addGate;

/// Writes like the real blocs: each under the tracked-day lock.
class _FakeMealDetailBloc extends Fake implements MealDetailBloc {
  @override
  Future<void> addIntake(
    BuildContext context,
    String unit,
    String amountText,
    IntakeTypeEntity type,
    MealEntity meal,
    DateTime day,
  ) => withTrackedDayLock(() async {
    await _addGate?.future;
    _dropLog.add('add');
  });
}

class _FakeHomeBloc extends Fake implements HomeBloc {
  @override
  Future<void> deleteIntakeItem(IntakeEntity intakeEntity) =>
      withTrackedDayLock(() async => _dropLog.add('delete'));

  @override
  void add(HomeEvent event) {}
}

class _FakeDiaryBloc extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

/// Single-profile stub: with only one profile the "Copy to profile" menu
/// item stays hidden, so the section menu matches its pre-multi-profile
/// shape in these tests.
class _SingleProfileGetProfilesUsecase implements GetProfilesUsecase {
  static final _profile = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026, 1, 1),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_profile];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _profile;
}

IntakeEntity _buildIntake({
  required double amount,
  required double kcal100,
  required double carbs100,
  required double fat100,
  required double protein100,
}) {
  return IntakeEntity(
    id: 'test-intake',
    unit: 'g',
    amount: amount,
    type: IntakeTypeEntity.breakfast,
    dateTime: DateTime(2026, 1, 1),
    meal: MealEntity(
      code: 'test-meal',
      name: 'Test Meal',
      url: null,
      mealQuantity: '100',
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: '100 g',
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal100,
        carbohydrates100: carbs100,
        fat100: fat100,
        proteins100: protein100,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    ),
  );
}

IntakeEntity _copy(IntakeEntity intake) => IntakeEntity(
  id: '${intake.id}-copy',
  unit: intake.unit,
  amount: intake.amount,
  type: intake.type,
  dateTime: intake.dateTime,
  meal: intake.meal,
);

Widget _wrapWithMaterial(Widget child) {
  return ChangeNotifierProvider<EnergyUnitProvider>(
    create: (_) => EnergyUnitProvider(),
    child: MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(() {
    final locator = GetIt.instance;
    locator.registerFactory<MealDetailBloc>(_FakeMealDetailBloc.new);
    locator.registerFactory<HomeBloc>(_FakeHomeBloc.new);
    locator.registerFactory<DiaryBloc>(_FakeDiaryBloc.new);
    locator.registerFactory<CalendarDayBloc>(_FakeCalendarDayBloc.new);
    locator.registerFactory<GetProfilesUsecase>(
      _SingleProfileGetProfilesUsecase.new,
    );
  });

  tearDownAll(() {
    GetIt.instance.reset();
  });

  // 100 g intake of food with 200 kcal/100g, 20 g carbs/100g, 10 g fat/100g, 5 g protein/100g
  // → totals: 200 kcal, 20 g C, 10 g F, 5 g P
  final intakes = [
    _buildIntake(
      amount: 100,
      kcal100: 200,
      carbs100: 20,
      fat100: 10,
      protein100: 5,
    ),
  ];

  // Protein, fat, carbs of the whole meal, under the header row.
  String macroLine() =>
      '${l10nEn.proteinLabelShort.toUpperCase()} 5 · '
      '${l10nEn.fatLabelShort.toUpperCase()} 10 · '
      '${l10nEn.carbsLabelShort.toUpperCase()} 20';

  String headerKcalOnly() => '200 ${l10nEn.kcalLabel}';

  testWidgets('passes macro sort to rows and drag feedback', (tester) async {
    await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
      day: DateTime(2026, 1, 1),
      title: 'Breakfast',
      listIcon: Icons.bakery_dining_outlined,
      addMealType: AddMealType.breakfastType,
      intakeList: intakes,
      usesImperialUnits: false,
      showMealMacros: false,
      sortType: DiarySortType.protein,
      onDeleteIntakeCallback: (_, _) {},
    )));
    await tester.pump();
    final card = find.byType(IntakeCard);
    expect(find.text('5.0 g protein'), findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(find.text('5.0 g protein'), findsOneWidget);
    expect(tester.widget<IntakeCard>(find.byType(IntakeCard)).sortType,
        DiarySortType.protein);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows kcal and the meal macros when showMealMacros is true',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
        day: DateTime(2026, 1, 1),
        title: 'Breakfast',
        listIcon: Icons.bakery_dining_outlined,
        addMealType: AddMealType.breakfastType,
        intakeList: intakes,
        usesImperialUnits: false,
        showMealMacros: true,
        onDeleteIntakeCallback: (_, _) {},
      )));
      await tester.pump();

      // The header and the single row under it show the same energy.
      expect(find.text(headerKcalOnly()), findsNWidgets(2));
      expect(find.text(macroLine()), findsOneWidget);
    },
  );

  testWidgets(
    'shows only kcal when showMealMacros is false',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
        day: DateTime(2026, 1, 1),
        title: 'Breakfast',
        listIcon: Icons.bakery_dining_outlined,
        addMealType: AddMealType.breakfastType,
        intakeList: intakes,
        usesImperialUnits: false,
        showMealMacros: false,
        onDeleteIntakeCallback: (_, _) {},
      )));
      await tester.pump();

      // The header and the single row under it show the same energy.
      expect(find.text(headerKcalOnly()), findsNWidgets(2));
      expect(find.text(macroLine()), findsNothing);
    },
  );

  testWidgets(
    'defaults to showing macro breakdown when showMealMacros is omitted',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
        day: DateTime(2026, 1, 1),
        title: 'Breakfast',
        listIcon: Icons.bakery_dining_outlined,
        addMealType: AddMealType.breakfastType,
        intakeList: intakes,
        usesImperialUnits: false,
        onDeleteIntakeCallback: (_, _) {},
      )));
      await tester.pump();

      expect(find.text(macroLine()), findsOneWidget);
    },
  );

  testWidgets('the compact header on Home shows the meal macros too', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
      day: DateTime(2026, 1, 1),
      title: 'Breakfast',
      listIcon: Icons.bakery_dining_outlined,
      addMealType: AddMealType.breakfastType,
      intakeList: [...intakes, ...intakes.map(_copy)],
      usesImperialUnits: false,
      compact: true,
      onDeleteIntakeCallback: (_, _) {},
    )));
    await tester.pump();

    expect(
      find.text(
        '${l10nEn.proteinLabelShort.toUpperCase()} 10 · '
        '${l10nEn.fatLabelShort.toUpperCase()} 20 · '
        '${l10nEn.carbsLabelShort.toUpperCase()} 40',
      ),
      findsOneWidget,
    );
  });

  testWidgets('on Home the entries are rows of one meal card', (tester) async {
    await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
      day: DateTime(2026, 1, 1),
      title: 'Breakfast',
      listIcon: Icons.bakery_dining_outlined,
      addMealType: AddMealType.breakfastType,
      intakeList: [...intakes, ...intakes.map(_copy)],
      usesImperialUnits: false,
      compact: true,
      onDeleteIntakeCallback: (_, _) {},
    )));
    await tester.pump();

    // One surface for the whole meal: the entries bring none of their own.
    expect(find.byType(AppCard), findsOneWidget);
    final card = find.byType(AppCard);
    expect(
      find.descendant(of: card, matching: find.text('Breakfast')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(IntakeCard)),
      findsNWidgets(2),
    );
  });

  testWidgets('a meal card lights up under an entry of another meal only', (
    tester,
  ) async {
    Widget meal(String title, List<IntakeEntity> entries) => IntakeVerticalList(
      day: DateTime(2026, 1, 1),
      title: title,
      listIcon: Icons.bakery_dining_outlined,
      addMealType: AddMealType.breakfastType,
      intakeList: entries,
      usesImperialUnits: false,
      compact: true,
      onDeleteIntakeCallback: (_, _) {},
    );
    await tester.pumpWidget(
      _wrapWithMaterial(
        Column(children: [meal('Breakfast', intakes), meal('Lunch', const [])]),
      ),
    );
    await tester.pump();

    Finder outlineOf(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byWidgetPredicate(
        // Material draws foreground painters of its own, so by name.
        (w) =>
            w is CustomPaint &&
            '${w.foregroundPainter.runtimeType}' == '_DashedOutlinePainter',
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(IntakeCard)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump();
    expect(outlineOf('Breakfast'), findsNothing);

    await gesture.moveTo(tester.getCenter(find.text('Lunch')));
    await tester.pump();
    expect(outlineOf('Lunch'), findsOneWidget);
    expect(outlineOf('Breakfast'), findsNothing);

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(outlineOf('Lunch'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows no header text when intake list is empty',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
        day: DateTime(2026, 1, 1),
        title: 'Breakfast',
        listIcon: Icons.bakery_dining_outlined,
        addMealType: AddMealType.breakfastType,
        intakeList: const [],
        usesImperialUnits: false,
        showMealMacros: true,
        onDeleteIntakeCallback: (_, _) {},
      )));
      await tester.pump();

      expect(find.text(macroLine()), findsNothing);
      expect(find.text(headerKcalOnly()), findsNothing);
    },
  );

  // Regression: the QR-share option was dropped from the popup menu when the
  // macros toggle PR landed on a stale base. Lock in the expected items so it
  // can't happen again silently. Import / paste-code are deliberately gone.
  testWidgets(
    'popup menu shows Copy/Delete/Share for non-empty section',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
        day: DateTime(2026, 1, 1),
        title: 'Breakfast',
        listIcon: Icons.bakery_dining_outlined,
        addMealType: AddMealType.breakfastType,
        intakeList: intakes,
        usesImperialUnits: false,
        showMealMacros: true,
        onCopyIntakeCallback: (_, _, _) {},
        onDeleteIntakeCallback: (_, _) {},
      )));
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<VerticalListPopupMenuSelections>));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.dialogCopyLabel), findsOneWidget);
      expect(find.text(l10nEn.deleteAllLabel), findsOneWidget);
      expect(find.text(l10nEn.shareMealLabel), findsOneWidget);
      expect(find.text(l10nEn.importMealLabel), findsNothing);
      expect(find.text(l10nEn.pasteCodeLabel), findsNothing);
    },
  );

  testWidgets(
    'no popup menu when section is empty',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(IntakeVerticalList(
        day: DateTime(2026, 1, 1),
        title: 'Breakfast',
        listIcon: Icons.bakery_dining_outlined,
        addMealType: AddMealType.breakfastType,
        intakeList: const [],
        usesImperialUnits: false,
        showMealMacros: true,
        onDeleteIntakeCallback: (_, _) {},
      )));
      await tester.pump();

      // Every menu entry acts on existing intakes, so an empty section has
      // no menu to open.
      expect(
        find.byType(PopupMenuButton<VerticalListPopupMenuSelections>),
        findsNothing,
      );
    },
  );

  // Regression: at a phone-width header the title used to be starved of space
  // by a Spacer competing with the kcal summary for flex, so "Breakfast"
  // wrapped onto a second line ("Breakfas" / "t"). The title now takes an
  // Expanded and shrinks to fit, so it must stay on exactly one line.
  testWidgets(
    'meal title stays on a single line beside the kcal summary',
    (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWithMaterial(
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 360,
            child: IntakeVerticalList(
              day: DateTime(2026, 1, 1),
              title: 'Breakfast',
              listIcon: Icons.bakery_dining_outlined,
              addMealType: AddMealType.breakfastType,
              intakeList: intakes,
              usesImperialUnits: false,
              showMealMacros: false,
              mealKcalTarget: 583,
              onDeleteIntakeCallback: (_, _) {},
            ),
          ),
        ),
      ));
      await tester.pump();

      // No RenderFlex overflow from the header competing for width.
      expect(tester.takeException(), isNull);

      final titleFinder = find.text('Breakfast');
      expect(titleFinder, findsOneWidget);
      // A single line of titleLarge (21px) renders around one line-height tall;
      // the old wrapped layout produced two lines (~double). Anything under
      // this threshold can only be a single line.
      final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
      expect(paragraph.size.height, lessThan(35));
    },
  );

  // The kcal line used to sit in a loose Flexible beside the Expanded title, so
  // it and the add button stopped at mid-row with a gap on the right.
  testWidgets('the compact header puts its add button at the right edge',
      (WidgetTester tester) async {
    // Wide enough that the kcal text is far narrower than half the row.
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrapWithMaterial(
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 700,
          child: IntakeVerticalList(
            day: DateTime(2026, 1, 1),
            title: 'Breakfast',
            listIcon: Icons.bakery_dining_outlined,
            addMealType: AddMealType.breakfastType,
            intakeList: const [],
            usesImperialUnits: false,
            compact: true,
            mealKcalTarget: 583,
            onDeleteIntakeCallback: (_, _) {},
          ),
        ),
      ),
    ));
    await tester.pump();

    final addButton = find.byIcon(Icons.add_rounded);
    expect(addButton, findsOneWidget);
    final right = tester.getTopRight(find.byType(IconButton)).dx;
    final edge = tester.getTopRight(find.byType(IntakeVerticalList)).dx;
    // 12 dp of header padding plus the button's own margin, not half a row.
    expect(edge - right, lessThan(24));
  });

  testWidgets('a profile switch queued during a drag between meals waits '
      'for the delete', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrapWithMaterial(
        IntakeVerticalList(
          day: DateTime(2026, 1, 1),
          title: 'Lunch',
          listIcon: Icons.lunch_dining_outlined,
          addMealType: AddMealType.lunchType,
          intakeList: const [],
          usesImperialUnits: false,
          onDeleteIntakeCallback: (_, _) {},
        ),
      ),
    );
    _dropLog.clear();
    _addGate = Completer<void>();
    addTearDown(() => _addGate = null);

    final target = tester.widget<DragTarget<IntakeEntity>>(
      find.byType(DragTarget<IntakeEntity>),
    );
    target.onAcceptWithDetails!(
      DragTargetDetails(data: intakes.single, offset: Offset.zero),
    );
    await tester.pump();
    // The switch takes the lock from the box swap on.
    final switched = withTrackedDayLock(() async => _dropLog.add('switch'));
    _addGate!.complete();
    await tester.pump();
    await switched;
    await tester.pump();

    expect(_dropLog, ['add', 'delete', 'switch']);
  });
}
