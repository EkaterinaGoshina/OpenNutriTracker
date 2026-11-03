import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Log a portion of [recipe] to a meal of today: how much, in portions or
/// grams, and which meal. The meal starts on the one the time of day suggests.
Future<void> showKitchenEatSheet(
  BuildContext context,
  RecipeEntity recipe,
) async {
  final config = await locator<GetConfigUsecase>().getConfig();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _KitchenEatSheet(
      recipe: recipe,
      initialType: MealTypeSuggester.suggestFromTime(
        DateTime.now(),
        mealSharesPct: config.mealKcalSharesPct,
      ),
    ),
  );
}

class _KitchenEatSheet extends StatefulWidget {
  final RecipeEntity recipe;
  final IntakeTypeEntity initialType;

  const _KitchenEatSheet({required this.recipe, required this.initialType});

  @override
  State<_KitchenEatSheet> createState() => _KitchenEatSheetState();
}

class _KitchenEatSheetState extends State<_KitchenEatSheet> {
  final _log = Logger('KitchenEatSheet');
  late final TextEditingController _amountController;
  late bool _byServing;
  late IntakeTypeEntity _type;
  bool _saving = false;

  bool get _hasServings =>
      widget.recipe.servingsCount != null && widget.recipe.servingsCount! > 0;

  @override
  void initState() {
    super.initState();
    // A dish with portions starts on one portion; one without is eaten by
    // weight, and the amount is the one thing left to type.
    _byServing = _hasServings;
    _amountController = TextEditingController(text: _byServing ? '1' : '');
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? get _quantity {
    final parsed = double.tryParse(_amountController.text.replaceAll(',', '.'));
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String get _unit => _byServing
      ? UnitDropdownItem.serving.toString()
      : UnitDropdownItem.g.toString();

  /// The amount in grams, which is what an intake stores.
  double? get _grams {
    final quantity = _quantity;
    if (quantity == null) return null;
    return convertQuantityToBaseUnit(
      quantity,
      _unit,
      widget.recipe.toMealEntity(),
    );
  }

  Future<void> _eat() async {
    final grams = _grams;
    if (grams == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final s = S.of(context);
    setState(() => _saving = true);
    try {
      await locator<MealDetailBloc>().addIntake(
        context,
        storedUnit(_unit),
        grams.toString(),
        _type,
        widget.recipe.toMealEntity(),
        DateTime.now(),
      );
      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.infoAddedIntakeLabel)));
    } catch (e, stackTrace) {
      _log.severe('Logging a portion of a dish failed', e, stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(s.logTrayLogFailedLabel)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final s = S.of(context);
    final meal = widget.recipe.toMealEntity();
    final grams = _grams;
    final kcal = grams == null
        ? null
        : grams * (meal.nutriments.energyPerUnit ?? 0);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing24,
          0,
          Dimens.spacing24,
          Dimens.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.recipe.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            if (_hasServings) ...[
              Semantics(
                identifier: 'kitchen-eat-unit',
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: true, label: Text(s.servingLabel)),
                    ButtonSegment(value: false, label: Text(s.gramUnit)),
                  ],
                  selected: {_byServing},
                  onSelectionChanged: (selection) => setState(() {
                    _byServing = selection.first;
                    // Start the other unit from a sensible value instead of
                    // reading "1" as one gram.
                    _amountController.text = _byServing ? '1' : '';
                  }),
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
            ],
            Semantics(
              identifier: 'kitchen-eat-amount',
              child: TextField(
                controller: _amountController,
                autofocus: !_byServing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*([.,]\d{0,2})?$'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: s.recipeIngredientAmountLabel,
                  suffixText: _byServing ? s.servingLabel : s.gramUnit,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final (type, label) in [
                  (IntakeTypeEntity.breakfast, s.breakfastLabel),
                  (IntakeTypeEntity.lunch, s.lunchLabel),
                  (IntakeTypeEntity.dinner, s.dinnerLabel),
                  (IntakeTypeEntity.snack, s.snackLabel),
                ])
                  Semantics(
                    identifier: 'kitchen-eat-meal-${type.name}',
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _type == type,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Dimens.spacing16),
            Text(
              kcal == null ? ' ' : EnergyDisplay.formatWithUnit(context, kcal),
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: Dimens.spacing8),
            Semantics(
              identifier: 'kitchen-eat-submit',
              child: FilledButton(
                onPressed: grams == null || _saving ? null : _eat,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                child: Text(s.kitchenEatButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
