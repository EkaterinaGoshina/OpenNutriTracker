import 'package:opennutritracker/core/domain/usecase/get_recent_ingredients_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';

/// [RecentMealBloc] for the ingredient picker, which also offers the foods
/// already used in dishes.
class RecentIngredientBloc extends RecentMealBloc {
  final GetRecentIngredientsUsecase _getRecentIngredientsUsecase;

  RecentIngredientBloc(
    this._getRecentIngredientsUsecase,
    super.getIntakeUsecase,
    super.getConfigUsecase,
  );

  @override
  Future<List<MealEntity>> loadRecentMeals() =>
      _getRecentIngredientsUsecase.getRecentIngredients();
}
