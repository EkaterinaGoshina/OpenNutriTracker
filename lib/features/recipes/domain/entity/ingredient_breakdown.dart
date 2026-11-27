import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// The four values on the dish's nutrition card that can be broken down.
enum BreakdownNutrient {
  energy,
  carbs,
  fat,
  protein;

  double? per100(MealNutrimentsEntity n) => switch (this) {
    energy => n.energyKcal100,
    carbs => n.carbohydrates100,
    fat => n.fat100,
    protein => n.proteins100,
  };
}

/// What one ingredient brings to the dish for the chosen nutrient.
class IngredientContribution {
  final RecipeIngredientEntity ingredient;

  /// Grams of the macro, or kcal for [BreakdownNutrient.energy]. Null when
  /// the product has no figure, which is not the same as zero.
  final double? amount;

  /// 0..1 of the known total.
  final double share;

  /// Energy this ingredient adds to the dish, null when unknown.
  final double? energyKcal;

  /// Grams of protein bought with 100 kcal of this product. Null when either
  /// figure is missing or the product has no energy.
  final double? proteinPer100Kcal;

  const IngredientContribution({
    required this.ingredient,
    required this.amount,
    required this.share,
    required this.energyKcal,
    required this.proteinPer100Kcal,
  });
}

class IngredientBreakdown {
  /// Biggest first; ingredients without a figure last. Ties keep the order of
  /// the dish.
  final List<IngredientContribution> items;
  final double total;

  const IngredientBreakdown({required this.items, required this.total});

  bool get hasMissingData => items.any((i) => i.amount == null);

  factory IngredientBreakdown.of(
    List<RecipeIngredientEntity> ingredients,
    BreakdownNutrient nutrient,
  ) {
    double? inDish(double? per100, RecipeIngredientEntity i) =>
        per100 == null ? null : per100 * i.convertedAmountG / 100;

    final amounts = [
      for (final i in ingredients)
        inDish(nutrient.per100(i.snapshotMeal.nutriments), i),
    ];
    final total = amounts.fold<double>(0, (sum, a) => sum + (a ?? 0));

    final order = List<int>.generate(ingredients.length, (i) => i)
      ..sort((a, b) {
        final left = amounts[a] ?? -1;
        final right = amounts[b] ?? -1;
        final byAmount = right.compareTo(left);
        return byAmount != 0 ? byAmount : a.compareTo(b);
      });

    return IngredientBreakdown(
      total: total,
      items: [
        for (final index in order)
          _contribution(
            ingredients[index],
            amounts[index],
            total,
            inDish(
              ingredients[index].snapshotMeal.nutriments.energyKcal100,
              ingredients[index],
            ),
          ),
      ],
    );
  }

  static IngredientContribution _contribution(
    RecipeIngredientEntity ingredient,
    double? amount,
    double total,
    double? energyKcal,
  ) {
    final n = ingredient.snapshotMeal.nutriments;
    final kcal100 = n.energyKcal100;
    final protein100 = n.proteins100;
    return IngredientContribution(
      ingredient: ingredient,
      amount: amount,
      share: total > 0 ? (amount ?? 0) / total : 0,
      energyKcal: energyKcal,
      proteinPer100Kcal: protein100 != null && kcal100 != null && kcal100 > 0
          ? protein100 / kcal100 * 100
          : null,
    );
  }
}
