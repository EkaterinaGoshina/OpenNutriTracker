import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/domain/entity/ingredient_breakdown.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_breakdown_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class RecipeNutritionSummary extends StatelessWidget {
  final MealNutrimentsEntity nutrimentsPer100;
  final double totalWeightG;

  /// With ingredients, a tap on a total shows which of them it came from.
  final List<RecipeIngredientEntity> ingredients;

  const RecipeNutritionSummary({
    super.key,
    required this.nutrimentsPer100,
    required this.totalWeightG,
    required this.ingredients,
  });

  double _total(double? per100) {
    return (per100 ?? 0) * totalWeightG / 100;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = theme.colorScheme.primary;
    // #177: energy values are stored as kcal; only the rendering layer
    // applies the kJ conversion when the user has selected that unit.
    final usesKilojoules = context.watch<EnergyUnitProvider>().usesKilojoules;
    final energyLabel = usesKilojoules ? s.kjLabel : s.kcalLabel;
    final energyTotalKcal = _total(nutrimentsPer100.energyKcal100);
    final energyTotalDisplay =
        usesKilojoules ? UnitCalc.kcalToKj(energyTotalKcal) : energyTotalKcal;
    final energyPer100Kcal = nutrimentsPer100.energyKcal100 ?? 0;
    final energyPer100Display = usesKilojoules
        ? UnitCalc.kcalToKj(energyPer100Kcal)
        : energyPer100Kcal;
    VoidCallback? open(BreakdownNutrient nutrient) => ingredients.isEmpty
        ? null
        : () => showIngredientBreakdownSheet(
            context,
            ingredients: ingredients,
            initialNutrient: nutrient,
          );
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.recipeNutritionPreviewLabel,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Dimens.spacing16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _NutrientCell(
                  value: energyTotalDisplay,
                  label: energyLabel,
                  color: accent,
                  palette: palette,
                  identifier: 'recipe-nutrition-energy',
                  onTap: open(BreakdownNutrient.energy),
                ),
              ),
              Expanded(
                child: _NutrientCell(
                  value: _total(nutrimentsPer100.carbohydrates100),
                  label: '${s.carbsLabel} ${s.gramUnit}',
                  color: palette.carbsText,
                  palette: palette,
                  identifier: 'recipe-nutrition-carbs',
                  onTap: open(BreakdownNutrient.carbs),
                ),
              ),
              Expanded(
                child: _NutrientCell(
                  value: _total(nutrimentsPer100.fat100),
                  label: '${s.fatLabel} ${s.gramUnit}',
                  color: palette.fatText,
                  palette: palette,
                  identifier: 'recipe-nutrition-fat',
                  onTap: open(BreakdownNutrient.fat),
                ),
              ),
              Expanded(
                child: _NutrientCell(
                  value: _total(nutrimentsPer100.proteins100),
                  label: '${s.proteinLabel} ${s.gramUnit}',
                  color: palette.proteinText,
                  palette: palette,
                  identifier: 'recipe-nutrition-protein',
                  onTap: open(BreakdownNutrient.protein),
                ),
              ),
            ],
          ),
          if (ingredients.isNotEmpty) ...[
            const SizedBox(height: Dimens.spacing8),
            Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 16,
                  color: palette.textMuted,
                ),
                const SizedBox(width: Dimens.spacing4),
                Expanded(
                  child: Text(
                    s.recipeBreakdownHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          Divider(height: Dimens.spacing24 + Dimens.spacing8, color: palette.border),
          Text(
            '${s.recipeNutritionPer100Label} · '
            '${energyPer100Display.toStringAsFixed(0)} $energyLabel · '
            '${s.carbsLabelShort.toUpperCase()} ${(nutrimentsPer100.carbohydrates100 ?? 0).toStringAsFixed(1)}g · '
            '${s.fatLabelShort.toUpperCase()} ${(nutrimentsPer100.fat100 ?? 0).toStringAsFixed(1)}g · '
            '${s.proteinLabelShort.toUpperCase()} ${(nutrimentsPer100.proteins100 ?? 0).toStringAsFixed(1)}g',
            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NutrientCell extends StatelessWidget {
  final double value;
  final String label;
  final Color color;
  final AppPalette palette;
  final String identifier;
  final VoidCallback? onTap;

  const _NutrientCell({
    required this.value,
    required this.label,
    required this.color,
    required this.palette,
    required this.identifier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      identifier: identifier,
      container: true,
      button: onTap != null,
      child: InkWell(
        borderRadius: Dimens.borderRadiusS,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
          child: Column(
            children: [
              Text(
                value.toStringAsFixed(0),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
