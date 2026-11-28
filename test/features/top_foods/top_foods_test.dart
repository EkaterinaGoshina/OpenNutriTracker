import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/top_foods/domain/top_foods.dart';

MealEntity _meal(
  String name, {
  String? code,
  double? kcal = 100,
  double? protein = 10,
  double? fat = 1,
  double? carbs = 1,
  MealSourceEntity source = MealSourceEntity.custom,
  String? backendSource,
}) => MealEntity(
  code: code ?? name,
  name: name,
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: '',
  source: source,
  backendSource: backendSource,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: carbs,
    fat100: fat,
    proteins100: protein,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
);

List<String?> _names(List<TopFood> foods) =>
    [for (final food in foods) food.meal.name];

void main() {
  test('ranks by protein per 100 kcal, or by the fewest calories', () {
    final top = TopFoods.of([
      _meal('cucumber', kcal: 15, protein: 0.8),
      _meal('chicken', kcal: 113, protein: 23.6),
      _meal('cottage cheese', kcal: 120, protein: 17),
    ]);

    expect(_names(top.ranked(sort: TopFoodsSort.protein)), [
      'chicken',
      'cottage cheese',
      'cucumber',
    ]);
    expect(_names(top.ranked(sort: TopFoodsSort.calories)), [
      'cucumber',
      'chicken',
      'cottage cheese',
    ]);
  });

  test('the calorie limit is inclusive', () {
    final top = TopFoods.of([
      _meal('at limit', kcal: 200),
      _meal('over', kcal: 201),
    ]);

    expect(_names(top.ranked(sort: TopFoodsSort.protein, maxKcal100: 200)), [
      'at limit',
    ]);
    expect(top.ranked(sort: TopFoodsSort.protein), hasLength(2));
  });

  test('the same food counts once and the first copy wins', () {
    final top = TopFoods.of([
      _meal('Tuna', code: '1', protein: 25),
      _meal('Tuna old', code: '1', protein: 20),
      _meal(' tuna ', code: '2', protein: 18),
    ]);

    expect(top.foods.single.proteins100, 25);
    expect(top.skippedCount, 0);
  });

  test('leaves out dishes and counts foods that cannot be compared', () {
    final top = TopFoods.of([
      _meal('soup', source: MealSourceEntity.recipe),
      _meal('no energy', kcal: null),
      _meal('zero energy', kcal: 0),
      _meal('no protein', protein: null),
      _meal('over 100 g of macros', protein: 80, fat: 40),
      _meal('a whole pizza', kcal: 1400),
      _meal(
        'portion',
        backendSource: MealEntity.wholePortionBackendSource,
      ),
      _meal('fine', fat: null, carbs: null),
    ]);

    expect(_names(top.foods), ['fine']);
    expect(top.skippedCount, 6);
  });
}
