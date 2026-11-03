import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/home/presentation/widgets/kitchen_eat_sheet.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_detail_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The home screen's kitchen: the dishes the user cooks, with a way to make a
/// new one, open one to edit it, and log a portion of one without going
/// through the add-food screen.
class KitchenCard extends StatefulWidget {
  const KitchenCard({super.key});

  /// How many dishes the card lists; the rest are one tap away under
  /// "All dishes".
  static const maxDishes = 2;

  @override
  State<KitchenCard> createState() => _KitchenCardState();
}

class _KitchenCardState extends State<KitchenCard> {
  late final RecipesBloc _bloc;

  /// Dishes swiped away and deleted, hidden at once: a [Dismissible] must be
  /// gone from the tree the frame it is dismissed, before the bloc reloads.
  final Set<String> _deletedIds = {};

  @override
  void initState() {
    super.initState();
    _bloc = locator<RecipesBloc>()..add(const LoadRecipesEvent());
  }

  Future<void> _open(String routeName, {Object? arguments}) async {
    await Navigator.of(context).pushNamed(routeName, arguments: arguments);
    if (mounted) _bloc.add(const LoadRecipesEvent());
  }

  /// Asks before deleting; the deletion itself happens only on a yes, so a
  /// cancelled swipe springs the row back.
  Future<bool> _confirmDelete(RecipeEntity dish) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.kitchenDeleteConfirmTitle),
        content: Text(s.recipeDeleteConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.dialogDeleteLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await locator<DeleteRecipeUseCase>().delete(dish.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing8,
      ),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing12,
          Dimens.spacing8,
          Dimens.spacing12,
        ),
        child: BlocBuilder<RecipesBloc, RecipesState>(
          bloc: _bloc,
          builder: (context, state) {
            final dishes = state is RecipesLoaded
                ? state.recipes
                      .where((d) => !_deletedIds.contains(d.id))
                      .toList()
                : const <RecipeEntity>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.kitchen_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: Dimens.spacing12),
                    Expanded(
                      child: Text(
                        S.of(context).kitchenTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (dishes.length > KitchenCard.maxDishes)
                      Semantics(
                        identifier: 'home-kitchen-all',
                        child: TextButton(
                          onPressed: () =>
                              _open(NavigationOptions.recipesRoute),
                          child: Text(S.of(context).kitchenAllDishes),
                        ),
                      ),
                    Semantics(
                      identifier: 'home-kitchen-create',
                      child: IconButton(
                        tooltip: S.of(context).kitchenCreateDish,
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () =>
                            _open(NavigationOptions.recipeBuilderRoute),
                      ),
                    ),
                  ],
                ),
                // Nothing until the dishes are read, so a user who has some
                // does not see "your dishes will appear here" for a moment.
                if (state is! RecipesLoaded)
                  const SizedBox.shrink()
                else if (dishes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: Dimens.spacing4,
                      right: Dimens.spacing8,
                      bottom: Dimens.spacing4,
                    ),
                    child: Text(
                      S.of(context).kitchenEmptyHint,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  )
                else
                  for (final dish in dishes.take(KitchenCard.maxDishes))
                    Dismissible(
                      key: ValueKey(dish.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(dish),
                      onDismissed: (_) {
                        setState(() => _deletedIds.add(dish.id));
                        _bloc.add(const LoadRecipesEvent());
                      },
                      background: const _DeleteBackground(),
                      child: _DishRow(
                        dish: dish,
                        onOpen: () => _open(
                          NavigationOptions.recipeDetailRoute,
                          arguments: RecipeDetailArguments(recipeId: dish.id),
                        ),
                        onEat: () => showKitchenEatSheet(context, dish),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What shows behind a dish row as it is swiped left.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: Dimens.spacing24),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: Dimens.borderRadiusM,
      ),
      child: Icon(Icons.delete_outline_rounded, color: colors.onErrorContainer),
    );
  }
}

class _DishRow extends StatelessWidget {
  final RecipeEntity dish;
  final VoidCallback onOpen;
  final VoidCallback onEat;

  const _DishRow({
    required this.dish,
    required this.onOpen,
    required this.onEat,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: Dimens.borderRadiusM,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                dish.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Semantics(
              identifier: 'home-kitchen-eat',
              child: FilledButton.tonal(
                onPressed: onEat,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(56, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing16,
                  ),
                ),
                child: Text(S.of(context).kitchenEatButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
