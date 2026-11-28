import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../../fixture/user_entity_fixtures.dart';

class _FakeBreakdownUsecase extends Fake implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;

  _FakeBreakdownUsecase(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: false),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUp(() {
    // The gauge navigates to KcalGoalInfoScreen, which pulls its usecase
    // from the locator when none is injected.
    locator.registerSingleton<GetKcalGoalBreakdownUsecase>(
      _FakeBreakdownUsecase(KcalGoalBreakdownEntity.compute(
        user: UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight,
        totalKcalActivities: 0,
      )),
    );
  });

  tearDown(() {
    GetIt.instance.reset();
  });

  DashboardWidget dashboardWidget({required double totalKcalLeft}) {
    return DashboardWidget(
      totalKcalSupplied: 2800,
      totalKcalBurned: 200,
      totalKcalDaily: 2500,
      totalKcalLeft: totalKcalLeft,
      totalCarbsIntake: 100,
      totalFatsIntake: 30,
      totalProteinsIntake: 60,
      totalCarbsGoal: 375,
      totalFatsGoal: 69,
      totalProteinsGoal: 93,
    );
  }

  testWidgets(
    'kcal gauge uses the error color when intake exceeds the daily goal',
    (tester) async {
      await tester.pumpWidget(_wrap(dashboardWidget(totalKcalLeft: -300)));
      await tester.pumpAndSettle();

      final gauge = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );

      expect(gauge.progressColor, ThemeData().colorScheme.error);
    },
  );

  testWidgets(
    'kcal gauge exposes a semantic tap action that opens the goal screen '
    '(regression: excludeSemantics stripped the GestureDetector tap, so '
    'screen readers announced a button that could not be activated)',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(dashboardWidget(totalKcalLeft: 1900)));
      await tester.pumpAndSettle();

      final gauge = tester.widget<CircularPercentIndicator>(
        find.byType(CircularPercentIndicator),
      );
      expect(gauge.progressColor, ThemeData().colorScheme.primary);

      final gaugeFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == 'home-kcal-gauge',
      );
      expect(gaugeFinder, findsOneWidget);

      final node = tester.getSemantics(gaugeFinder);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'excludeSemantics drops the GestureDetector\'s tap action, '
            'so the Semantics node must register its own onTap',
      );

      // Activate the node the way TalkBack/VoiceOver do — via the semantic
      // action, not a pointer tap.
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      expect(find.byType(KcalGoalInfoScreen), findsOneWidget);

      semanticsHandle.dispose();
    },
  );

  testWidgets('tapping a macro lists what gave it today, biggest first',
      (tester) async {
    IntakeEntity intake(String name, double protein, IntakeTypeEntity type) =>
        IntakeEntity(
          id: name,
          unit: 'g',
          amount: 100,
          type: type,
          dateTime: DateTime(2026, 11, 28),
          meal: MealEntity(
            code: name,
            name: name,
            url: null,
            mealQuantity: null,
            mealUnit: 'g',
            servingQuantity: null,
            servingUnit: 'g',
            servingSize: null,
            nutriments: MealNutrimentsEntity(
              energyKcal100: 200,
              carbohydrates100: 10,
              fat100: 5,
              proteins100: protein,
              sugars100: null,
              saturatedFat100: null,
              fiber100: null,
            ),
            source: MealSourceEntity.custom,
          ),
        );

    await tester.pumpWidget(
      _wrap(
        DashboardWidget(
          totalKcalSupplied: 400,
          totalKcalBurned: 0,
          totalKcalDaily: 2500,
          totalKcalLeft: 2100,
          totalCarbsIntake: 20,
          totalFatsIntake: 10,
          totalProteinsIntake: 40,
          totalCarbsGoal: 375,
          totalFatsGoal: 69,
          totalProteinsGoal: 93,
          intakes: [
            intake('Bun', 10, IntakeTypeEntity.breakfast),
            intake('Chicken', 30, IntakeTypeEntity.lunch),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier('home-macro-protein'));
    await tester.pumpAndSettle();

    final s = S.of(tester.element(find.byType(DashboardWidget)));
    expect(find.text(s.dayBreakdownTitle), findsOneWidget);
    expect(find.text(s.dayBreakdownTotal('40 ${s.gramUnit}')), findsOneWidget);
    expect(find.text('30 ${s.gramUnit} · 75%'), findsOneWidget);
    expect(find.textContaining(s.lunchLabel), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chicken')).dy,
      lessThan(tester.getTopLeft(find.text('Bun')).dy),
    );
  });
}
