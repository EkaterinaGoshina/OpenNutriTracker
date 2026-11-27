import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recent_ingredients_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

/// Recents in the ingredient picker were built from the diary alone, so a
/// food added to a dish never showed up there.
void main() {
  late IntakeRepository intakeRepo;
  late RecipeRepository recipeRepo;
  late GetRecentIngredientsUsecase usecase;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init('.');
    registerHiveAdaptersOnce();
    final provider = FakeHiveDBProvider(
      intakeBox: await Hive.openBox<IntakeDBO>('recent_ingredients_intake'),
      recipeBox: await Hive.openBox<RecipeDBO>('recent_ingredients_recipe'),
    );
    intakeRepo = IntakeRepository(IntakeDataSource(provider));
    recipeRepo = RecipeRepository(RecipeDataSource(provider));
    usecase = GetRecentIngredientsUsecase(
      GetIntakeUsecase(intakeRepo, recipeRepo),
      recipeRepo,
    );
  });

  tearDown(() async => Hive.deleteFromDisk());

  const nutriments = MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: null,
    fat100: null,
    proteins100: null,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  );

  MealEntity food(String name) => MealEntity(
    code: name,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: null,
    servingSize: null,
    nutriments: nutriments,
    source: MealSourceEntity.off,
  );

  Future<void> saveDish(String id, DateTime updatedAt, List<String> foods) =>
      recipeRepo.saveRecipe(
        RecipeEntity(
          id: id,
          name: id,
          description: null,
          ingredients: [
            for (final name in foods)
              RecipeIngredientEntity(
                snapshotMeal: food(name),
                amount: 100,
                unit: 'g',
                convertedAmountG: 100,
              ),
          ],
          totalWeightG: 100.0 * foods.length,
          aggregatedNutrimentsPer100: nutriments,
          createdAt: updatedAt,
          updatedAt: updatedAt,
          servingsCount: null,
        ),
      );

  Future<void> log(String name, DateTime at) => intakeRepo.addIntake(
    IntakeEntity(
      id: name,
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.lunch,
      meal: food(name),
      dateTime: at,
    ),
  );

  Future<List<String?>> names() async =>
      (await usecase.getRecentIngredients()).map((m) => m.name).toList();

  test('an ingredient of a saved dish is recent without a diary entry', () async {
    await saveDish('soup', DateTime(2026, 11, 20), ['carrot', 'onion']);

    expect(await names(), ['carrot', 'onion']);
  });

  test('dishes and diary are merged newest first without repeats', () async {
    await saveDish('old', DateTime(2026, 11, 1), ['rice', 'onion']);
    await log('apple', DateTime(2026, 11, 10));
    await log('onion', DateTime(2026, 11, 5));
    await saveDish('new', DateTime(2026, 11, 20), ['carrot', 'onion']);

    expect(await names(), ['carrot', 'onion', 'apple', 'rice']);
  });

  test('nothing saved or logged means an empty list', () async {
    expect(await names(), isEmpty);
  });
}
