import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/food_search_tab_view.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_list_item.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_quantity_dialog.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Search that stays open while ingredients are added one after another.
///
/// Each pick asks for its amount, goes straight into the recipe being built
/// and shows up in the list under the search; the screen closes only on the
/// Done button. [startCount] is how many ingredients the recipe already had on
/// the way in, so the list shows just what was added here.
class IngredientPickerScreen extends StatelessWidget {
  final RecipeBuilderBloc bloc;
  final int startCount;

  const IngredientPickerScreen({
    super.key,
    required this.bloc,
    required this.startCount,
  });

  Future<void> _onMealSelected(BuildContext context, MealEntity meal) async {
    final selection = await showIngredientQuantityDialog(context, meal: meal);
    if (selection == null) return;
    bloc.add(
      AddIngredientEvent(
        meal: meal,
        amount: selection.amount,
        unit: selection.unit,
      ),
    );
  }

  /// For a food the search does not have: fill in its values, and it comes
  /// back here as the next ingredient (and stays in the food list).
  Future<void> _onCreatePressed(BuildContext context) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    final created = await Navigator.of(context).pushNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments.pick(
        usesImperialUnits: config.usesImperialFoodUnits,
      ),
    );
    if (created is MealEntity && context.mounted) {
      await _onMealSelected(context, created);
    }
  }

  Future<void> _onBarcodePressed(BuildContext context) async {
    // The scanner in pick mode pops the meal back instead of routing into the
    // logging flow; it then takes the same path as a tap on a search result.
    final scannedMeal = await Navigator.of(context).pushNamed(
      NavigationOptions.scannerRoute,
      arguments: ScannerScreenArguments.pick(),
    );
    if (scannedMeal is MealEntity && context.mounted) {
      await _onMealSelected(context, scannedMeal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).recipeAddIngredientLabel),
        actions: [
          Semantics(
            identifier: 'recipe-ingredient-picker-create',
            child: IconButton(
              tooltip: S.of(context).noResultsCreateCustomFood,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _onCreatePressed(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FoodSearchTabView(
              onMealSelected: (meal) => _onMealSelected(context, meal),
              onBarcodePressed: () => _onBarcodePressed(context),
              onCreateCustomFood: () => _onCreatePressed(context),
            ),
          ),
          BlocBuilder<RecipeBuilderBloc, RecipeBuilderState>(
            bloc: bloc,
            builder: (context, state) {
              final added = state.ingredients.length > startCount
                  ? state.ingredients.sublist(startCount)
                  : const [];
              if (added.isEmpty) return const SizedBox.shrink();
              return Container(
                decoration: BoxDecoration(
                  color: palette.surface,
                  border: Border(
                    top: BorderSide(
                      color: palette.border,
                      width: Dimens.hairline,
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Dimens.spacing16,
                      Dimens.spacing8,
                      Dimens.spacing16,
                      Dimens.spacing8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          S
                              .of(context)
                              .recipeIngredientCountLabel(added.length),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                        // Bounded so a long list leaves the search its room.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.25,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: added.length,
                            itemBuilder: (context, i) => IngredientListItem(
                              ingredient: added[i],
                              onRemove: () => bloc.add(
                                RemoveIngredientEvent(startCount + i),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Dimens.spacing8),
                        Semantics(
                          identifier: 'recipe-ingredient-picker-done',
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              S.of(context).recipeIngredientsDoneLabel,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
