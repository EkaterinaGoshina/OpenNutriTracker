import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/recipe_nutrition_summary.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../../helpers/test_l10n.dart';

RecipeIngredientEntity _ingredient(
  String name,
  double grams, {
  required double kcal100,
  double? protein100,
}) {
  return RecipeIngredientEntity(
    snapshotMeal: MealEntity(
      code: name,
      name: name,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal100,
        carbohydrates100: 1,
        fat100: 1,
        proteins100: protein100,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    ),
    amount: grams,
    unit: 'g',
    convertedAmountG: grams,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<RecipeIngredientEntity> ingredients,
  bool kilojoules = false,
}) async {
  // A narrow phone, where a long name and its figures have the least room.
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(usesKilojoules: kilojoules),
      child: MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: RecipeNutritionSummary(
            nutrimentsPer100: MealNutrimentsEntity.empty(),
            totalWeightG: 120,
            ingredients: ingredients,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final ingredients = [
    _ingredient('Cheese', 20, kcal100: 360, protein100: 25),
    _ingredient(
      'Chicken breast with a name far too long for one line',
      100,
      kcal100: 115,
      protein100: 23,
    ),
    _ingredient('Sauce', 30, kcal100: 80),
  ];

  testWidgets('tapping protein ranks the ingredients by protein', (
    tester,
  ) async {
    await _pump(tester, ingredients: ingredients);

    await tester.tap(find.bySemanticsIdentifier('recipe-nutrition-protein'));
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.recipeBreakdownTotal('28 g')), findsOneWidget);
    expect(find.text('23 g · 82%'), findsOneWidget);
    expect(find.text('5.0 g · 18%'), findsOneWidget);
    expect(
      find.text(l10nEn.recipeBreakdownProteinPerEnergy('20.0', 'kcal')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.textContaining('Chicken')).dy,
      lessThan(tester.getTopLeft(find.text('Cheese')).dy),
    );
    expect(find.text(l10nEn.recipeBreakdownNoData), findsOneWidget);
    expect(find.text(l10nEn.recipeBreakdownMissingNote), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('recipe-breakdown-tab-energy'));
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.recipeBreakdownTotal('211 kcal')), findsOneWidget);
    expect(find.textContaining('per 100'), findsNothing);
    expect(find.text(l10nEn.recipeBreakdownMissingNote), findsNothing);
  });

  testWidgets('protein per energy follows the kilojoule setting', (
    tester,
  ) async {
    await _pump(tester, ingredients: ingredients, kilojoules: true);

    await tester.tap(find.bySemanticsIdentifier('recipe-nutrition-protein'));
    await tester.pumpAndSettle();

    // 23 g in 115 kcal is 20 g per 100 kcal, or 4.8 g per 100 kJ.
    expect(
      find.text(l10nEn.recipeBreakdownProteinPerEnergy('4.8', 'kJ')),
      findsOneWidget,
    );
  });

  testWidgets('with no ingredients there is nothing to open', (tester) async {
    await _pump(tester, ingredients: const []);

    expect(find.text(l10nEn.recipeBreakdownHint), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('recipe-nutrition-protein'));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.recipeBreakdownTitle), findsNothing);
  });
}
