import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/family/data/account_repository.dart';
import 'package:opennutritracker/features/family/data/family_repository.dart';
import 'package:opennutritracker/features/family/domain/entity/family_entity.dart';
import 'package:opennutritracker/features/family/domain/entity/family_portion_entity.dart';
import 'package:opennutritracker/features/family/presentation/widgets/family_widgets.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Log a portion of [recipe] to a meal of today: how much, in portions or
/// grams, and which meal. The meal starts on the one the time of day suggests.
///
/// For someone signed in to a family with other members there is a second
/// mode: the cook serves the dish to everyone at the table, one amount per
/// person, and each portion lands in that person's own diary.
Future<void> showKitchenEatSheet(
  BuildContext context,
  RecipeEntity recipe,
) async {
  final config = await locator<GetConfigUsecase>().getConfig();
  if (!context.mounted) return;
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EatSheet(
      name: recipe.name,
      meal: recipe.toMealEntity(),
      hasServings: recipe.servingsCount != null && recipe.servingsCount! > 0,
      initialType: MealTypeSuggester.suggestFromTime(
        DateTime.now(),
        mealSharesPct: config.mealKcalSharesPct,
      ),
    ),
  );
}

/// The cook serves any single food, not only a dish from the kitchen: rice, a
/// loaf of bread, anything found in search or scanned. Opens straight in the
/// family mode, one amount per person. Returns true when the portions were
/// served, so the caller can leave its own screen the way "Add" does.
Future<bool> showServeFamilySheet(
  BuildContext context, {
  required MealEntity meal,
  required IntakeTypeEntity initialType,
  DateTime? day,
}) async {
  final served = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EatSheet(
      name: meal.name ?? '?',
      meal: meal,
      // A serving only when the app can scale it (#629).
      hasServings: meal.scalableServingQuantity != null,
      initialType: initialType,
      day: day,
      familyOnly: true,
    ),
  );
  return served == true;
}

/// Whether this build can serve anyone: a family project is set up and
/// someone is signed in. Whether they have a family with others in it is only
/// known once the sheet reads it.
bool familyServingAvailable() =>
    locator.isRegistered<FamilyRepository>() &&
    locator<AccountRepository>().currentUser != null;

class _EatSheet extends StatefulWidget {
  final String name;
  final MealEntity meal;
  final bool hasServings;
  final IntakeTypeEntity initialType;

  /// The day the portions are logged on; now when null.
  final DateTime? day;

  /// True when opened only to serve the family (from a food's detail screen,
  /// where logging for oneself is the screen's own "Add").
  final bool familyOnly;

  const _EatSheet({
    required this.name,
    required this.meal,
    required this.hasServings,
    required this.initialType,
    this.day,
    this.familyOnly = false,
  });

  @override
  State<_EatSheet> createState() => _EatSheetState();
}

class _EatSheetState extends State<_EatSheet> {
  final _log = Logger('EatSheet');
  late final TextEditingController _amountController;
  late bool _byServing;
  late IntakeTypeEntity _type;
  bool _saving = false;

  /// The signed-in user's family and who they are in it, once read. Null
  /// without an account, without a family, or while the read is out.
  FamilyEntity? _family;
  String? _myId;
  bool _forFamily = false;
  final Map<String, TextEditingController> _memberAmounts = {};

  /// Ids for this attempt's portions, kept across a retry so a portion the
  /// server already has is not served twice. Dropped when anything the cook
  /// typed changes.
  final Map<String, String> _portionIds = {};

  bool get _hasServings => widget.hasServings;

  /// True once the family read has answered, with or without a family.
  bool _familyRead = false;

  @override
  void initState() {
    super.initState();
    // A dish with portions starts on one portion; one without is eaten by
    // weight, and the amount is the one thing left to type.
    _byServing = _hasServings;
    _amountController = TextEditingController(text: _byServing ? '1' : '');
    _type = widget.initialType;
    _forFamily = widget.familyOnly;
    _loadFamily();
  }

  @override
  void dispose() {
    _amountController.dispose();
    for (final c in _memberAmounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Reads the family in the background; the sheet is usable at once and the
  /// "for the family" switch appears if there is someone to serve.
  Future<void> _loadFamily() async {
    if (!familyServingAvailable()) {
      _familyRead = true;
      return;
    }
    final me = locator<AccountRepository>().currentUser!;
    try {
      final family = await locator<FamilyRepository>().getMyFamily();
      if (!mounted) return;
      if (family == null || family.members.length < 2) {
        setState(() => _familyRead = true);
        return;
      }
      setState(() {
        _familyRead = true;
        _family = family;
        _myId = me.id;
        for (final m in family.members) {
          _memberAmounts[m.userId] = TextEditingController(
            text: _byServing ? '1' : '',
          );
        }
      });
    } catch (e) {
      // Offline or signed out: the sheet stays as it was, for one person.
      _log.info('Reading the family for the kitchen sheet failed', e);
      if (mounted) setState(() => _familyRead = true);
    }
  }

  /// Everyone at the table, the cook first.
  List<FamilyMemberEntity> get _people {
    final members = _family?.members ?? const <FamilyMemberEntity>[];
    return [
      ...members.where((m) => m.userId == _myId),
      ...members.where((m) => m.userId != _myId),
    ];
  }

  double? _gramsOf(String text) {
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return null;
    return convertQuantityToBaseUnit(parsed, _unit, widget.meal);
  }

  /// Every amount back to the unit's starting value, as when the unit flips.
  void _resetAmounts() {
    _portionIds.clear();
    final start = _byServing ? '1' : '';
    _amountController.text = start;
    for (final c in _memberAmounts.values) {
      c.text = start;
    }
  }

  double? get _quantity {
    final parsed = double.tryParse(_amountController.text.replaceAll(',', '.'));
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String get _unit => _byServing
      ? UnitDropdownItem.serving.toString()
      : (widget.meal.isLiquid
            ? UnitDropdownItem.ml.toString()
            : UnitDropdownItem.g.toString());

  String _baseUnitLabel(S s) =>
      widget.meal.isLiquid ? s.milliliterUnit : s.gramUnit;

  /// The amount in grams, which is what an intake stores.
  double? get _grams {
    final quantity = _quantity;
    if (quantity == null) return null;
    return convertQuantityToBaseUnit(quantity, _unit, widget.meal);
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
        widget.meal,
        DateTime.now(),
      );
      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(s.infoAddedIntakeLabel)));
    } catch (e, stackTrace) {
      _log.severe('Logging a portion of a dish failed', e, stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(s.logTrayLogFailedLabel)));
    }
  }

  /// Total energy of everything typed in family mode.
  double? _familyKcal() {
    final energy = widget.meal.nutriments.energyPerUnit ?? 0;
    var total = 0.0;
    var any = false;
    for (final c in _memberAmounts.values) {
      final grams = _gramsOf(c.text);
      if (grams == null) continue;
      any = true;
      total += grams * energy;
    }
    return any ? total : null;
  }

  bool get _hasFamilyAmounts =>
      _memberAmounts.values.any((c) => _gramsOf(c.text) != null);

  /// The cook's own portion goes into their diary, everyone else's to the
  /// server for their phones to pick up. The server goes first: if it
  /// fails nothing has been logged anywhere and the cook can simply retry.
  Future<void> _serve() async {
    if (_saving || !_hasFamilyAmounts) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final s = S.of(context);
    final meal = widget.meal;
    final now = widget.day ?? DateTime.now();
    final myId = _myId;
    setState(() => _saving = true);
    try {
      final others = <PortionToServe>[];
      IntakeEntity? mine;
      for (final person in _people) {
        final grams = _gramsOf(_memberAmounts[person.userId]!.text);
        if (grams == null) continue;
        final intake = IntakeEntity(
          id: _portionIds.putIfAbsent(person.userId, IdGenerator.getUniqueID),
          unit: storedUnit(_unit),
          amount: grams,
          type: _type,
          meal: meal,
          dateTime: now,
        );
        if (person.userId == myId) {
          mine = intake;
        } else {
          others.add(
            PortionToServe(
              id: intake.id,
              recipientId: person.userId,
              intake: intake,
            ),
          );
        }
      }
      if (others.isNotEmpty) {
        await locator<FamilyRepository>().servePortions(others);
      }
      if (mine != null) {
        await locator<MealDetailBloc>().addIntakeEntity(mine);
      }
      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(s.serveFamilyDone)));
    } catch (e, stackTrace) {
      _log.severe('Serving a dish to the family failed', e, stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${s.serveFamilyFailed} ${familyErrorText(s, e)}'),
        ),
      );
    }
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
    required String identifier,
    bool autofocus = false,
  }) {
    final s = S.of(context);
    return Semantics(
      identifier: identifier,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*([.,]\d{0,2})?$')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: _byServing ? s.servingLabel : _baseUnitLabel(s),
        ),
        onChanged: (_) => setState(_portionIds.clear),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final s = S.of(context);
    final meal = widget.meal;
    final grams = _grams;
    final kcal = _forFamily
        ? _familyKcal()
        : grams == null
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
              widget.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            if (_family != null && !widget.familyOnly) ...[
              Semantics(
                identifier: 'kitchen-eat-mode',
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(s.serveFamilyModeSelf),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.soup_kitchen_rounded),
                      label: Text(s.serveFamilyModeFamily),
                    ),
                  ],
                  selected: {_forFamily},
                  onSelectionChanged: (selection) =>
                      setState(() => _forFamily = selection.first),
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
            ],
            if (_hasServings) ...[
              Semantics(
                identifier: 'kitchen-eat-unit',
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: true, label: Text(s.servingLabel)),
                    ButtonSegment(value: false, label: Text(_baseUnitLabel(s))),
                  ],
                  selected: {_byServing},
                  onSelectionChanged: (selection) => setState(() {
                    _byServing = selection.first;
                    // Start the other unit from a sensible value instead of
                    // reading "1" as one gram.
                    _resetAmounts();
                  }),
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
            ],
            if (widget.familyOnly && _family == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing16),
                child: _familyRead
                    ? Text(
                        s.serveFamilyUnavailable,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              )
            else if (_forFamily) ...[
              Text(
                s.serveFamilyHint,
                style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: Dimens.spacing8),
              for (final person in _people) ...[
                _amountField(
                  controller: _memberAmounts[person.userId]!,
                  label: person.userId == _myId
                      ? s.serveFamilyMe
                      : (person.displayName.isEmpty
                            ? s.servedByCookLabel
                            : person.displayName),
                  identifier: 'kitchen-serve-${person.userId}',
                ),
                const SizedBox(height: Dimens.spacing8),
              ],
            ] else
              _amountField(
                controller: _amountController,
                label: s.recipeIngredientAmountLabel,
                identifier: 'kitchen-eat-amount',
                autofocus: !_byServing,
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
                      onSelected: (_) => setState(() {
                        _type = type;
                        _portionIds.clear();
                      }),
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
                onPressed: _saving
                    ? null
                    : _forFamily
                    ? (_hasFamilyAmounts ? _serve : null)
                    : (grams == null ? null : _eat),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  _forFamily ? s.serveFamilySubmit : s.kitchenEatButton,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
