import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// One amount of the food worth showing: 100 g, the whole pack, a serving.
typedef SavedAmount = ({String title, double grams});

/// What the food will hold once saved, worked out as the user types, so
/// nobody has to guess whether the numbers entered end up per 100 g or for the
/// whole product.
class SavedNutritionCard extends StatelessWidget {
  /// The typed values brought to 100 g/ml. Null where the field is empty.
  /// Energy is in the unit on screen, [energyUnit].
  final double? energyPer100;
  final double? carbsPer100;
  final double? fatPer100;
  final double? proteinPer100;
  final String energyUnit;

  /// The rows, in order.
  final List<SavedAmount> amounts;

  /// Shown instead of the rows while there is nothing to work out.
  final String? placeholder;

  const SavedNutritionCard({
    super.key,
    required this.energyPer100,
    required this.carbsPer100,
    required this.fatPer100,
    required this.proteinPer100,
    required this.energyUnit,
    required this.amounts,
    this.placeholder,
  });

  /// One decimal, dropped when it is zero.
  static String _number(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final muted = textTheme.bodyMedium?.copyWith(color: palette.textMuted);

    String scaled(double? per100, double grams) =>
        per100 == null ? '–' : _number(per100 * grams / 100);

    return Semantics(
      identifier: 'edit-meal-saved-summary',
      child: AppCard(
        color: palette.surfaceMuted,
        padding: const EdgeInsets.all(Dimens.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.editFoodSummaryTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (placeholder != null) ...[
              const SizedBox(height: Dimens.spacing4),
              Text(placeholder!, style: muted),
            ] else
              for (final amount in amounts) ...[
                const SizedBox(height: Dimens.spacing12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        amount.title,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing8),
                    Text(
                      '${scaled(energyPer100, amount.grams)} $energyUnit',
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Dimens.spacing4),
                Text(
                  s.editFoodSummaryMacros(
                    scaled(carbsPer100, amount.grams),
                    scaled(fatPer100, amount.grams),
                    scaled(proteinPer100, amount.grams),
                  ),
                  style: muted,
                ),
              ],
          ],
        ),
      ),
    );
  }
}
