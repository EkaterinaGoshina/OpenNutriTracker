import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/dish_shelf_life.dart';

void main() {
  test('suggested expiry is the cooking day plus the default shelf life', () {
    expect(
      DishShelfLife.suggestedExpiry(DateTime(2026, 11, 29, 18, 30)),
      DateTime(2026, 12, 2),
    );
  });

  test('a dish is not expired on its last day, and is the day after', () {
    final expires = DateTime(2026, 11, 24);
    expect(
      DishShelfLife.isExpired(expires, DateTime(2026, 11, 24, 23, 59)),
      isFalse,
    );
    expect(
      DishShelfLife.isExpired(expires, DateTime(2026, 11, 25, 0, 1)),
      isTrue,
    );
  });

  test('no expiry date means never expired', () {
    expect(DishShelfLife.isExpired(null, DateTime(2030)), isFalse);
  });
}
