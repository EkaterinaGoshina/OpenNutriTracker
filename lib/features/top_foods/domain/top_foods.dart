import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// What the top is ordered by.
enum TopFoodsSort { protein, calories }

/// A food that can be ranked: its energy and protein per 100 g/ml are known.
class TopFood {
  final MealEntity meal;
  final double kcal100;
  final double proteins100;

  const TopFood({
    required this.meal,
    required this.kcal100,
    required this.proteins100,
  });

  /// How much protein 100 kcal of this food buys.
  double get proteinPer100Kcal => proteins100 / kcal100 * 100;
}

/// The user's own foods, ready to be ranked per 100 g/ml.
class TopFoods {
  /// Pure fat is about 900 kcal per 100 g; anything above is not per 100 g.
  static const _maxPlausibleKcal100 = 920;

  final List<TopFood> foods;

  /// Foods left out because they cannot be compared per 100 g: no energy or
  /// protein, figures that cannot be per 100 g, or a whole-portion entry.
  final int skippedCount;

  const TopFoods({required this.foods, required this.skippedCount});

  /// [meals] come in order of trust: where the same food is there twice, the
  /// first one wins. Dishes are left out, the top is about products.
  factory TopFoods.of(Iterable<MealEntity> meals) {
    final seenKeys = <String>{};
    final seenNames = <String>{};
    final foods = <TopFood>[];
    var skipped = 0;
    for (final meal in meals) {
      if (meal.source == MealSourceEntity.recipe) continue;
      final name = meal.name?.trim().toLowerCase() ?? '';
      if (name.isEmpty) continue;
      final key = meal.code ?? name;
      // Both are recorded even for a duplicate: each quick add of one food
      // gets its own code, and an edit can change a code but keep the name.
      final newKey = seenKeys.add(key);
      final newName = seenNames.add(
        '$name|${meal.brands?.trim().toLowerCase() ?? ''}',
      );
      if (!newKey || !newName) continue;

      final nutriments = meal.nutriments;
      final kcal = nutriments.energyKcal100;
      final proteins = nutriments.proteins100;
      if (meal.backendSource == MealEntity.wholePortionBackendSource ||
          kcal == null ||
          kcal <= 0 ||
          kcal > _maxPlausibleKcal100 ||
          proteins == null ||
          !isNutrimentsConsistent(nutriments)) {
        skipped++;
        continue;
      }
      foods.add(TopFood(meal: meal, kcal100: kcal, proteins100: proteins));
    }
    return TopFoods(foods: foods, skippedCount: skipped);
  }

  /// Best first. [maxKcal100] keeps only foods at or under that energy, so a
  /// protein powder does not head a list of light foods.
  List<TopFood> ranked({required TopFoodsSort sort, double? maxKcal100}) {
    int byProtein(TopFood a, TopFood b) =>
        b.proteinPer100Kcal.compareTo(a.proteinPer100Kcal);
    int byCalories(TopFood a, TopFood b) => a.kcal100.compareTo(b.kcal100);
    final (first, second) = switch (sort) {
      TopFoodsSort.protein => (byProtein, byCalories),
      TopFoodsSort.calories => (byCalories, byProtein),
    };
    return [
      for (final food in foods)
        if (maxKcal100 == null || food.kcal100 <= maxKcal100) food,
    ]..sort((a, b) {
      final result = first(a, b);
      return result != 0 ? result : second(a, b);
    });
  }
}
