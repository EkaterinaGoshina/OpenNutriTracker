import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/features/recipes/domain/entity/ingredient_breakdown.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_breakdown_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// "Which food gave me all this protein today?", opened from a macro on the
/// home card. Each diary entry is listed on its own, with its meal, so the same
/// food eaten twice shows twice.
Future<void> showDayBreakdownSheet(
  BuildContext context, {
  required List<IntakeEntity> intakes,
  required BreakdownNutrient initialNutrient,
  required bool usesImperialUnits,
}) {
  final s = S.of(context);
  // By identity: two equal entries are still two rows with their own meal.
  final byRow = Map<RecipeIngredientEntity, IntakeEntity>.identity();
  final rows = <RecipeIngredientEntity>[];
  for (final intake in intakes) {
    // A diary amount is already in the unit its food is counted per, which is
    // what the breakdown multiplies by.
    final row = RecipeIngredientEntity(
      snapshotMeal: intake.meal,
      amount: intake.amount,
      unit: intake.unit,
      convertedAmountG: intake.amount,
    );
    byRow[row] = intake;
    rows.add(row);
  }
  String mealLabel(IntakeTypeEntity type) => switch (type) {
    IntakeTypeEntity.breakfast => s.breakfastLabel,
    IntakeTypeEntity.lunch => s.lunchLabel,
    IntakeTypeEntity.dinner => s.dinnerLabel,
    IntakeTypeEntity.snack => s.snackLabel,
  };

  return showIngredientBreakdownSheet(
    context,
    ingredients: rows,
    initialNutrient: initialNutrient,
    title: s.dayBreakdownTitle,
    totalLabel: s.dayBreakdownTotal,
    emptyLabel: s.dayBreakdownEmpty,
    amountLabel: (row) {
      final intake = byRow[row]!;
      final amount = MealValueUnitText(
        value: intake.amount,
        meal: intake.meal,
        usesImperialUnits: usesImperialUnits,
      ).format(context);
      return '${mealLabel(intake.type)} · $amount';
    },
  );
}
