import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:opennutritracker/core/presentation/widgets/image_full_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_placeholder.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/extensions.dart';

/// The top of the product screen: name, brand and package size, with the photo
/// as a small square beside them. The numbers below are what the screen is
/// for, so the photo takes no more than that; a tap opens it full size. A food
/// without a photo gets no placeholder.
class MealTitleExpanded extends StatelessWidget {
  static const photoSize = 88.0;

  final MealEntity meal;
  final bool usesImperialUnits;

  const MealTitleExpanded({
    super.key,
    required this.meal,
    required this.usesImperialUnits,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final brands = meal.brands ?? '';
    final hasPhoto =
        meal.localImagePath != null || (meal.mainImageUrl ?? '').isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPhoto) ...[
          _MealPhoto(meal: meal),
          const SizedBox(width: Dimens.spacing16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                meal.name ?? '',
                style: textTheme.headlineSmall?.copyWith(
                  color: palette.textStrong,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (brands.isNotEmpty) ...[
                const SizedBox(height: Dimens.spacing4),
                Text(
                  brands,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (meal.mealQuantity != null) ...[
                const SizedBox(height: Dimens.spacing4),
                MealValueUnitText(
                  value: meal.mealQuantity?.toLenientDoubleOrNull() ?? 0,
                  meal: meal,
                  usesImperialUnits: usesImperialUnits,
                  textStyle: textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                  prefix: '${S.of(context).mealSizeLabel}: ',
                ),
              ],
              // Disclosure for unreviewed machine-translated food names from
              // the backend's translation table.
              if (meal.machineTranslatedName)
                Padding(
                  padding: const EdgeInsets.only(top: Dimens.spacing4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        size: 12,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: Dimens.spacing4),
                      Flexible(
                        child: Text(
                          S.of(context).machineTranslatedNameHint,
                          style: textTheme.labelSmall?.copyWith(
                            color: palette.textMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The attached photo when there is one, the remote product image otherwise.
class _MealPhoto extends StatelessWidget {
  final MealEntity meal;

  const _MealPhoto({required this.meal});

  @override
  Widget build(BuildContext context) {
    final local = meal.localImagePath;
    final url = meal.mainImageUrl ?? '';
    return ClipRRect(
      borderRadius: Dimens.borderRadiusM,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pushNamed(
          NavigationOptions.imageFullScreenRoute,
          arguments: ImageFullScreenArguments(url, localImagePath: local),
        ),
        child: Hero(
          tag: ImageFullScreen.fullScreenHeroTag,
          child: SizedBox.square(
            dimension: MealTitleExpanded.photoSize,
            child: local != null
                ? UserImage(
                    relativePath: local,
                    fallback: const MealPlaceholder(),
                    width: MealTitleExpanded.photoSize,
                    height: MealTitleExpanded.photoSize,
                  )
                : CachedNetworkImage(
                    cacheManager: locator<CacheManager>(),
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, string) => const MealPlaceholder(),
                    errorWidget: (context, url, error) =>
                        const MealPlaceholder(),
                  ),
          ),
        ),
      ),
    );
  }
}
