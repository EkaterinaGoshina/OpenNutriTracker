import 'package:collection/collection.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// Recents for the ingredient picker: the foods put into saved dishes along
/// with the ones logged in the diary, newest first, each food once. Adding an
/// ingredient writes no diary entry, so the diary alone leaves them out.
class GetRecentIngredientsUsecase {
  final GetIntakeUsecase _getIntakeUsecase;
  final RecipeRepository _recipeRepository;

  GetRecentIngredientsUsecase(this._getIntakeUsecase, this._recipeRepository);

  Future<List<MealEntity>> getRecentIngredients() async {
    final used = <(DateTime, MealEntity)>[
      for (final intake in await _getIntakeUsecase.getRecentIntake())
        (intake.dateTime, intake.meal),
      for (final recipe in _recipeRepository.getAllRecipes())
        for (final ingredient in recipe.ingredients)
          (recipe.updatedAt, _asItIsNow(ingredient.snapshotMeal)),
    ];
    // Stable, so the ingredients of one dish keep the order they have in it.
    mergeSort(used, compare: (a, b) => b.$1.compareTo(a.$1));

    final seen = <String>{};
    return [
      for (final (_, meal) in used)
        if (seen.add(meal.code ?? meal.name ?? '')) meal,
    ];
  }

  /// A dish used inside another dish is offered as it is now, as in the diary
  /// recents; a deleted one keeps its snapshot.
  MealEntity _asItIsNow(MealEntity meal) {
    final code = meal.code;
    if (meal.source != MealSourceEntity.recipe || code == null) return meal;
    return _recipeRepository.getRecipeById(code)?.toMealEntity() ?? meal;
  }
}
