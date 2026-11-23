/// Shelf-life helpers for home-cooked dishes.
///
/// There is no public source that knows how long *this* dish keeps, so the
/// app does not look it up online. It offers the general food-safety rule
/// for cooked leftovers kept in the fridge (USDA/FSIS: 3 to 4 days) and
/// leaves the real date to the user. The expiry stays optional.
class DishShelfLife {
  DishShelfLife._();

  /// Conservative end of the USDA "3 to 4 days" range.
  static const int suggestedDays = 3;

  /// The day [suggestedDays] after [cookedAt], at midnight.
  static DateTime suggestedExpiry(DateTime cookedAt) =>
      DateTime(cookedAt.year, cookedAt.month, cookedAt.day + suggestedDays);

  /// True when [expiresAt] is a day before [now]. A dish is still fine on
  /// its last day.
  static bool isExpired(DateTime? expiresAt, DateTime now) {
    if (expiresAt == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
    return last.isBefore(today);
  }
}
