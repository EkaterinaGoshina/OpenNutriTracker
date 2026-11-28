import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/get_favourite_meals_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recent_ingredients_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/top_foods/domain/top_foods.dart';

/// Collects every food the user has already added: their own products, their
/// favourites, the diary and the ingredients of saved dishes. Nothing is
/// stored for the top itself, so it follows every edit on its own.
class GetTopFoodsUsecase {
  final CustomMealDataSource _customMealDataSource;
  final GetFavouriteMealsUsecase _getFavouriteMealsUsecase;
  final GetRecentIngredientsUsecase _getRecentIngredientsUsecase;

  GetTopFoodsUsecase(
    this._customMealDataSource,
    this._getFavouriteMealsUsecase,
    this._getRecentIngredientsUsecase,
  );

  Future<TopFoods> getTopFoods() async => TopFoods.of([
    // The user's own library first: it holds the latest values of a food
    // that older diary entries may still show as it was.
    ..._customMealDataSource.getAllCustomMeals().map(MealEntity.fromMealDBO),
    ...await _getFavouriteMealsUsecase.getAllFavourites(),
    ...await _getRecentIngredientsUsecase.getRecentIngredients(),
  ]);
}
