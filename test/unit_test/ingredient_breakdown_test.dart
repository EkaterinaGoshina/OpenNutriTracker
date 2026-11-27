import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/domain/entity/ingredient_breakdown.dart';

RecipeIngredientEntity _ingredient(
  String name,
  double grams, {
  double? kcal100,
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
        carbohydrates100: null,
        fat100: null,
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

void main() {
  List<String?> names(IngredientBreakdown b) => [
    for (final i in b.items) i.ingredient.snapshotMeal.name,
  ];

  test('ranks by what each ingredient puts into the dish', () {
    final breakdown = IngredientBreakdown.of([
      _ingredient('onion', 200, kcal100: 40, protein100: 1),
      _ingredient('chicken', 100, kcal100: 115, protein100: 23),
      _ingredient('cheese', 20, kcal100: 360, protein100: 25),
    ], BreakdownNutrient.protein);

    expect(names(breakdown), ['chicken', 'cheese', 'onion']);
    expect(breakdown.total, closeTo(30, 1e-9));
    expect(breakdown.items.first.amount, closeTo(23, 1e-9));
    expect(breakdown.items.first.share, closeTo(23 / 30, 1e-9));
    expect(breakdown.items.first.energyKcal, closeTo(115, 1e-9));
    expect(breakdown.items.first.proteinPer100Kcal, closeTo(20, 1e-9));
    expect(breakdown.hasMissingData, isFalse);
  });

  test('a missing figure goes last and is not read as zero', () {
    final breakdown = IngredientBreakdown.of([
      _ingredient('mystery', 100, kcal100: 50),
      _ingredient('water', 100, kcal100: 0, protein100: 0),
      _ingredient('egg', 100, kcal100: 150, protein100: 12),
    ], BreakdownNutrient.protein);

    expect(names(breakdown), ['egg', 'water', 'mystery']);
    expect(breakdown.items.last.amount, isNull);
    expect(breakdown.items[1].amount, 0);
    expect(
      breakdown.items[1].proteinPer100Kcal,
      isNull,
      reason: 'no energy to divide by',
    );
    expect(breakdown.hasMissingData, isTrue);
  });

  test('an all-zero total gives zero shares, and ties keep dish order', () {
    final breakdown = IngredientBreakdown.of([
      _ingredient('first', 10, protein100: 0),
      _ingredient('second', 10, protein100: 0),
    ], BreakdownNutrient.protein);

    expect(names(breakdown), ['first', 'second']);
    expect(breakdown.items.every((i) => i.share == 0), isTrue);
  });
}
