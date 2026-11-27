import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/features/recipes/domain/entity/ingredient_breakdown.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_quantity_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Bottom sheet answering "which ingredient brought this much protein?",
/// opened from a value on the dish's nutrition card.
Future<void> showIngredientBreakdownSheet(
  BuildContext context, {
  required List<RecipeIngredientEntity> ingredients,
  required BreakdownNutrient initialNutrient,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _IngredientBreakdownSheet(
      ingredients: ingredients,
      initialNutrient: initialNutrient,
    ),
  );
}

class _IngredientBreakdownSheet extends StatefulWidget {
  final List<RecipeIngredientEntity> ingredients;
  final BreakdownNutrient initialNutrient;

  const _IngredientBreakdownSheet({
    required this.ingredients,
    required this.initialNutrient,
  });

  @override
  State<_IngredientBreakdownSheet> createState() =>
      _IngredientBreakdownSheetState();
}

class _IngredientBreakdownSheetState extends State<_IngredientBreakdownSheet> {
  late BreakdownNutrient _nutrient = widget.initialNutrient;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final breakdown = IngredientBreakdown.of(widget.ingredients, _nutrient);
    final color = switch (_nutrient) {
      BreakdownNutrient.energy => theme.colorScheme.primary,
      BreakdownNutrient.carbs => palette.carbs,
      BreakdownNutrient.fat => palette.fat,
      BreakdownNutrient.protein => palette.protein,
    };
    String chipLabel(BreakdownNutrient n) => switch (n) {
      BreakdownNutrient.energy => EnergyDisplay.unitLabel(context),
      BreakdownNutrient.carbs => s.carbsLabel,
      BreakdownNutrient.fat => s.fatLabel,
      BreakdownNutrient.protein => s.proteinLabel,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.recipeBreakdownTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Dimens.spacing4),
                Text(
                  s.recipeBreakdownTotal(_format(breakdown.total)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: Dimens.spacing12),
                Wrap(
                  spacing: Dimens.spacing8,
                  children: [
                    for (final n in BreakdownNutrient.values)
                      Semantics(
                        identifier: 'recipe-breakdown-tab-${n.name}',
                        child: ChoiceChip(
                          label: Text(chipLabel(n)),
                          selected: n == _nutrient,
                          // No checkmark: with it the four chips wrap on a
                          // phone. The outline marks the choice instead.
                          showCheckmark: false,
                          padding: const EdgeInsets.all(Dimens.spacing8),
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: Dimens.spacing4,
                          ),
                          selectedColor: color.withValues(alpha: 0.24),
                          side: BorderSide(
                            color: n == _nutrient ? color : Colors.transparent,
                            width: 2,
                          ),
                          onSelected: (_) => setState(() => _nutrient = n),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing8,
                Dimens.spacing16,
                Dimens.spacing24,
              ),
              children: [
                for (final item in breakdown.items)
                  _ContributionRow(
                    item: item,
                    nutrient: _nutrient,
                    color: color,
                    palette: palette,
                  ),
                if (breakdown.hasMissingData)
                  Text(
                    s.recipeBreakdownMissingNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The total in the unit of the selected chip.
  String _format(double total) => _nutrient == BreakdownNutrient.energy
      ? EnergyDisplay.formatWithUnit(context, total)
      : '${_grams(total)} ${S.of(context).gramUnit}';
}

/// One decimal under 10 g, so a spoon of something does not read as "0".
String _grams(double value) => value > 0 && value < 10
    ? value.toStringAsFixed(1)
    : value.round().toString();

class _ContributionRow extends StatelessWidget {
  final IngredientContribution item;
  final BreakdownNutrient nutrient;
  final Color color;
  final AppPalette palette;

  const _ContributionRow({
    required this.item,
    required this.nutrient,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final ingredient = item.ingredient;
    final amountStr = ingredient.amount % 1 == 0
        ? ingredient.amount.toStringAsFixed(0)
        : ingredient.amount.toStringAsFixed(1);

    final amount = item.amount;
    final String value;
    if (amount == null) {
      value = s.recipeBreakdownNoData;
    } else {
      final shown = nutrient == BreakdownNutrient.energy
          ? EnergyDisplay.formatWithUnit(context, amount)
          : '${_grams(amount)} ${s.gramUnit}';
      value = '$shown · ${(item.share * 100).round()}%';
    }

    // The price in energy: how much each macro costs in this product. Only
    // protein gets "per 100 kcal", since more carbs or fat per calorie is not
    // a reason to prefer a food.
    final details = <String>[
      '$amountStr ${ingredientUnitLabel(context, ingredient.unit)}',
      if (nutrient != BreakdownNutrient.energy && item.energyKcal != null)
        EnergyDisplay.formatWithUnit(context, item.energyKcal!),
    ];
    final String? efficiency;
    final perKcal = item.proteinPer100Kcal;
    if (nutrient == BreakdownNutrient.protein && perKcal != null) {
      // Per 100 of whichever unit is on screen: 100 kJ is less food than
      // 100 kcal, so it buys proportionally less protein.
      final perUnit = perKcal / EnergyDisplay.convert(context, 1);
      efficiency = s.recipeBreakdownProteinPerEnergy(
        perUnit.toStringAsFixed(1),
        EnergyDisplay.unitLabel(context),
      );
    } else {
      efficiency = null;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing16),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ingredient.snapshotMeal.name ?? '?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.spacing8),
                Text(
                  value,
                  style: amount == null
                      ? muted
                      : textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                ),
              ],
            ),
            const SizedBox(height: Dimens.spacing4),
            LinearProgressIndicator(
              value: item.share.clamp(0, 1).toDouble(),
              minHeight: Dimens.spacing8,
              color: color,
              backgroundColor: palette.surfaceMuted,
              borderRadius: Dimens.borderRadiusS,
            ),
            const SizedBox(height: Dimens.spacing4),
            Text(details.join(' · '), style: muted),
            if (efficiency != null)
              Text(
                efficiency,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
