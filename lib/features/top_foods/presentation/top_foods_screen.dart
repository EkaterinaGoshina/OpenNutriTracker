import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/top_foods/domain/get_top_foods_usecase.dart';
import 'package:opennutritracker/features/top_foods/domain/top_foods.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The foods the user has already added, best first: the most protein for the
/// calories, or simply the fewest calories, per 100 g/ml.
class TopFoodsScreen extends StatefulWidget {
  const TopFoodsScreen({super.key});

  @override
  State<TopFoodsScreen> createState() => _TopFoodsScreenState();
}

class _TopFoodsScreenState extends State<TopFoodsScreen> {
  /// The calorie ceilings on offer, kcal per 100 g/ml; null is no ceiling.
  static const _limits = <double?>[100, 200, null];

  TopFoodsSort _sort = TopFoodsSort.protein;
  double? _maxKcal100 = 200;
  late Future<TopFoods> _topFoods = _load();

  Future<TopFoods> _load() => locator<GetTopFoodsUsecase>().getTopFoods();

  /// Opens the product, where it can be logged or corrected.
  Future<void> _open(TopFood food) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    final now = DateTime.now();
    await Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        food.meal,
        MealTypeSuggester.suggestFromTime(
          now,
          mealSharesPct: config.mealKcalSharesPct,
        ),
        now,
        config.usesImperialFoodUnits,
      ),
    );
    if (mounted) setState(() => _topFoods = _load());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);

    return Scaffold(
      appBar: AppBar(title: Text(s.topFoodsTitle)),
      body: FutureBuilder<TopFoods>(
        future: _topFoods,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(s.topFoodsError));
          }
          final topFoods = snapshot.data;
          if (topFoods == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final ranked = topFoods.ranked(
            sort: _sort,
            maxKcal100: _maxKcal100,
          );
          return ListView(
            padding: const EdgeInsets.all(Dimens.spacing16),
            children: [
              Semantics(
                identifier: 'top-foods-sort',
                child: SegmentedButton<TopFoodsSort>(
                  // The checkmark would wrap the longer label on a phone.
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: TopFoodsSort.protein,
                      label: Text(s.topFoodsSortProtein),
                    ),
                    ButtonSegment(
                      value: TopFoodsSort.calories,
                      label: Text(s.topFoodsSortCalories),
                    ),
                  ],
                  selected: {_sort},
                  onSelectionChanged: (selection) =>
                      setState(() => _sort = selection.first),
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
              Wrap(
                spacing: Dimens.spacing8,
                children: [
                  for (final limit in _limits)
                    Semantics(
                      identifier:
                          'top-foods-limit-${limit?.round() ?? 'all'}',
                      child: ChoiceChip(
                        label: Text(
                          limit == null
                              ? s.topFoodsLimitAll
                              : s.topFoodsLimitUnder(
                                  EnergyDisplay.formatWithUnit(context, limit),
                                ),
                        ),
                        selected: limit == _maxKcal100,
                        onSelected: (_) => setState(() => _maxKcal100 = limit),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Dimens.spacing8),
              Text(s.topFoodsPer100Note, style: muted),
              const SizedBox(height: Dimens.spacing12),
              if (ranked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: Dimens.spacing32,
                  ),
                  child: Text(
                    topFoods.foods.isEmpty
                        ? s.topFoodsEmpty
                        : s.topFoodsEmptyForLimit,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              for (final (index, food) in ranked.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                  child: _TopFoodRow(
                    place: index + 1,
                    food: food,
                    palette: palette,
                    onTap: () => _open(food),
                  ),
                ),
              if (topFoods.skippedCount > 0) ...[
                const SizedBox(height: Dimens.spacing8),
                Text(
                  s.topFoodsSkippedNote(topFoods.skippedCount),
                  style: muted,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TopFoodRow extends StatelessWidget {
  final int place;
  final TopFood food;
  final AppPalette palette;
  final VoidCallback onTap;

  const _TopFoodRow({
    required this.place,
    required this.food,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final meal = food.meal;
    final brand = meal.brands?.trim() ?? '';
    String grams(double? value) => value == null
        ? '—'
        : value > 0 && value < 10
        ? value.toStringAsFixed(1)
        : value.round().toString();
    final macros = s.topFoodsMacros(
      grams(food.proteins100),
      grams(meal.nutriments.fat100),
      grams(meal.nutriments.carbohydrates100),
    );
    // Per 100 of whichever energy unit is on screen, as in the ingredient
    // breakdown.
    final perEnergy =
        food.proteinPer100Kcal / EnergyDisplay.convert(context, 1);

    return AppCard(
      borderRadius: Dimens.radiusM,
      onTap: onTap,
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: Dimens.spacing32,
              child: Text('$place', style: textTheme.titleMedium),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (brand.isNotEmpty)
                    Text(
                      brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  const SizedBox(height: Dimens.spacing4),
                  Text(macros, style: muted),
                  Text(
                    s.recipeBreakdownProteinPerEnergy(
                      perEnergy.toStringAsFixed(1),
                      EnergyDisplay.unitLabel(context),
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.proteinText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Text(
              EnergyDisplay.formatWithUnit(context, food.kcal100),
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
