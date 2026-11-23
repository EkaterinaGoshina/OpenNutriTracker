import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/utils/dish_shelf_life.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The one-line date summary of a dish: "Good until Tue, Nov 26", or
/// "Expired ..." once that day has passed. Falls back to the cooking date when
/// no expiry is set, and is null when the dish has neither.
String? dishDatesLine(BuildContext context, RecipeEntity dish) {
  final s = S.of(context);
  final l10n = MaterialLocalizations.of(context);
  final expires = dish.expiresAt;
  if (expires != null) {
    final date = l10n.formatMediumDate(expires);
    return DishShelfLife.isExpired(expires, DateTime.now())
        ? s.kitchenDishExpired(date)
        : s.kitchenDishGoodUntil(date);
  }
  final cooked = dish.cookedAt;
  if (cooked != null) return s.kitchenDishCooked(l10n.formatMediumDate(cooked));
  return null;
}
