import 'dart:async';
import 'dart:math' as math;


import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image_picker_tile.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/barcode_validator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/food_name_validator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/widgets/default_meal_image.dart';
import 'package:opennutritracker/features/edit_meal/presentation/widgets/saved_nutrition_card.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class EditMealScreen extends StatefulWidget {
  const EditMealScreen({super.key});

  @override
  State<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends State<EditMealScreen> {
  final log = Logger('EditMealScreen');
  late MealEntity _mealEntity;
  late DateTime _day;
  late IntakeTypeEntity _intakeTypeEntity;
  late bool _usesImperialUnits;
  LogTray? _logTray;

  late bool _editOnly;
  late bool _pickMode;

  late EditMealBloc _editMealBloc;

  final _nameTextController = TextEditingController();
  final _brandsTextController = TextEditingController();
  final _barcodeTextController = TextEditingController();
  final _mealQuantityTextController = TextEditingController();
  final _servingQuantityTextController = TextEditingController();
  final _baseQuantityTextController = TextEditingController();
  final _kcalTextController = TextEditingController();
  final _carbsTextController = TextEditingController();
  final _fatTextController = TextEditingController();
  final _proteinTextController = TextEditingController();
  // Advanced-mode micronutrient controllers (#232 follow-up: all 10 panel nutrients)
  final _fiberTextController = TextEditingController();
  final _saturatedFatTextController = TextEditingController();
  final _sugarsTextController = TextEditingController();
  final _sodiumTextController = TextEditingController();
  final _calciumTextController = TextEditingController();
  final _ironTextController = TextEditingController();
  final _potassiumTextController = TextEditingController();
  final _magnesiumTextController = TextEditingController();
  final _vitaminDTextController = TextEditingController();
  final _vitaminB12TextController = TextEditingController();

  final _units = ['g', 'ml'];
  String selectedUnit = 'g';

  /// Whether the nutrition values are typed for 100 g/ml, as most packaging
  /// prints them, or for the weight in [_baseQuantityTextController].
  bool _per100 = true;

  /// The energy and macro fields as they were filled in on opening, so the
  /// consistency checks only speak about numbers the user has touched.
  late String _initialNutritionTexts;

  /// The micronutrient fields as they were filled in on opening.
  final Map<TextEditingController, String> _initialMicroTexts = {};
  // Default on so behaviour matches what existing users are used to — the
  // meal is saved to their custom list unless they actively untick the box.
  // #249 adds the *option* to skip the save; it does not change the default.
  bool _saveForLater = true;

  // didChangeDependencies is called on every dependency change, including
  // ones triggered by Navigator pops returning from sub-pages (the barcode
  // scanner among them). Without this guard the controllers would get
  // re-seeded from _mealEntity.code on every return, wiping a value the
  // user just scanned into the field.
  bool _initialised = false;

  /// Tracks the unit the energy field was last rendered in, so that when
  /// the user flips between kcal and kJ in Settings mid-edit we can
  /// re-display the same underlying energy in the new unit. `null` until
  /// the first build seeds the field.
  bool? _lastRenderedUsesKj;

  // #64 follow-up: user-attached photo for a custom meal. Mirrors
  // _mealEntity.localImagePath but is held separately so the picker
  // can update the on-screen preview before the parent entity is
  // rebuilt at save time.
  String? _localImagePath;
  bool _localImageCleared = false;

  @override
  void initState() {
    super.initState();
    // Initialize once, not during build.
    _editMealBloc = locator<EditMealBloc>();
    _editMealBloc.add(InitializeEditMealEvent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as EditMealScreenArguments;
    _mealEntity = args.mealEntity;
    _day = args.day;
    _intakeTypeEntity = args.intakeTypeEntity;
    _usesImperialUnits = args.usesImperialUnits;
    _editOnly = args.editOnly;
    _pickMode = args.pickMode;
    _logTray = args.logTray;

    _nameTextController.text = _mealEntity.name ?? "";
    _brandsTextController.text = _mealEntity.brands ?? "";
    // MealEntity.code is dual-purpose: it carries a real product barcode for
    // OFF / FDC scans, but for custom meals MealEntity.empty() seeds it with
    // an internal UUID that the user should never see in the Barcode input.
    // Only show codes that actually look like a retail barcode (8–14 digits);
    // anything else means there isn't a user-visible barcode yet.
    final existingCode = _mealEntity.code;
    _barcodeTextController.text =
        (existingCode != null && isBarcodeFormatValid(existingCode))
            ? existingCode
            : "";
    _mealQuantityTextController.text =
        _mealEntity.mealQuantity?.withDotDecimal() ?? "";
    _servingQuantityTextController.text =
        _mealEntity.servingQuantity.toStringOrEmpty();
    // Seed the energy field in the user's currently-selected unit (#177
    // follow-up). Storage stays kcal — we only translate at the edges.
    final usesKjOnLoad =
        Provider.of<EnergyUnitProvider>(context, listen: false).usesKilojoules;
    _kcalTextController.text = _formatStoredKcalForDisplay(
      _mealEntity.nutriments.energyKcal100,
      usesKjOnLoad,
    );
    _lastRenderedUsesKj = usesKjOnLoad;
    _carbsTextController.text =
        _mealEntity.nutriments.carbohydrates100.toStringOrEmpty();
    _fatTextController.text = _mealEntity.nutriments.fat100.toStringOrEmpty();
    _proteinTextController.text =
        _mealEntity.nutriments.proteins100.toStringOrEmpty();
    _fiberTextController.text =
        _mealEntity.nutriments.fiber100.toStringOrEmpty();
    _saturatedFatTextController.text =
        _mealEntity.nutriments.saturatedFat100.toStringOrEmpty();
    _sugarsTextController.text =
        _mealEntity.nutriments.sugars100.toStringOrEmpty();
    _sodiumTextController.text =
        _mealEntity.nutriments.sodium100.toStringOrEmpty();
    _calciumTextController.text =
        _mealEntity.nutriments.calcium100.toStringOrEmpty();
    _ironTextController.text =
        _mealEntity.nutriments.iron100.toStringOrEmpty();
    _potassiumTextController.text =
        _mealEntity.nutriments.potassium100.toStringOrEmpty();
    _magnesiumTextController.text =
        _mealEntity.nutriments.magnesium100.toStringOrEmpty();
    _vitaminDTextController.text =
        _mealEntity.nutriments.vitaminD100.toStringOrEmpty();
    _vitaminB12TextController.text =
        _mealEntity.nutriments.vitaminB12100.toStringOrEmpty();
    _localImagePath = _mealEntity.localImagePath;
    selectedUnit = _switchButtonUnit(_mealEntity.mealUnit);

    // Convert meal size to imperial units if necessary
    if (_usesImperialUnits) {
      _mealQuantityTextController.text = _convertToImperial(
        _mealQuantityTextController.text,
        _mealEntity.mealUnit ?? "0",
      );
      _servingQuantityTextController.text = _convertToImperial(
        _servingQuantityTextController.text,
        _mealEntity.mealUnit ?? "0",
      );
    }

    _initialNutritionTexts = _nutritionTexts();
    for (final controller in _microControllers) {
      _initialMicroTexts[controller] = controller.text;
    }
  }

  List<TextEditingController> get _microControllers => [
    _fiberTextController,
    _saturatedFatTextController,
    _sugarsTextController,
    _sodiumTextController,
    _calciumTextController,
    _ironTextController,
    _potassiumTextController,
    _magnesiumTextController,
    _vitaminDTextController,
    _vitaminB12TextController,
  ];

  String _nutritionTexts() => [
    _kcalTextController.text,
    _carbsTextController.text,
    _fatTextController.text,
    _proteinTextController.text,
  ].join('|');

  @override
  void dispose() {
    _nameTextController.dispose();
    _brandsTextController.dispose();
    _barcodeTextController.dispose();
    _mealQuantityTextController.dispose();
    _servingQuantityTextController.dispose();
    _baseQuantityTextController.dispose();
    _kcalTextController.dispose();
    _carbsTextController.dispose();
    _fatTextController.dispose();
    _proteinTextController.dispose();
    // Do not close _editMealBloc here if provided as a singleton by locator.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the energy-unit provider so the form reacts when the user
    // flips between kcal and kJ in Settings while this screen is open.
    final usesKj = context.watch<EnergyUnitProvider>().usesKilojoules;
    _maybeReinterpretKcalField(usesKj);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return SafeArea(
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
          title: Text(
            S.of(context).editMealLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Semantics(
            identifier: 'edit-meal-save',
            child: FilledButton(
              onPressed: () => _onSavePressed(_usesImperialUnits),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const RoundedRectangleBorder(
                  borderRadius: Dimens.borderRadiusM,
                ),
              ),
              child: Text(S.of(context).buttonSaveLabel),
            ),
          ),
        ),
        body: BlocBuilder<EditMealBloc, EditMealState>(
          bloc: _editMealBloc,
          builder: (BuildContext context, EditMealState state) {
            if (state is EditMealLoadingState) {
              return _getLoadingContent();
            } else if (state is EditMealLoadedState) {
              return _getLoadedContent(state.usesImperialUnits, usesKj);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  /// Re-interpret whatever the user has typed in the energy field when
  /// the active energy unit changes mid-edit. The current text is
  /// interpreted as the previously-rendered unit, converted to the new
  /// unit, and written back so the displayed quantity matches the new
  /// unit suffix. We round to one decimal place to keep the field tidy.
  void _maybeReinterpretKcalField(bool usesKj) {
    if (_lastRenderedUsesKj == null || _lastRenderedUsesKj == usesKj) {
      _lastRenderedUsesKj = usesKj;
      return;
    }
    final current = double.tryParse(_kcalTextController.text);
    if (current != null) {
      final converted = usesKj
          ? UnitCalc.kcalToKj(current)
          : UnitCalc.kjToKcal(current);
      _kcalTextController.text =
          double.parse(converted.toStringAsFixed(1)).toStringOrEmpty();
    }
    _lastRenderedUsesKj = usesKj;
  }

  /// Convert a stored kcal value into the string the user should see in
  /// the energy field, given the active unit. One decimal place is
  /// plenty for an input field; saving rounds back to kcal anyway.
  String _formatStoredKcalForDisplay(double? storedKcal, bool usesKj) {
    if (storedKcal == null) return "";
    final display = usesKj ? UnitCalc.kcalToKj(storedKcal) : storedKcal;
    return double.parse(display.toStringAsFixed(1)).toStringOrEmpty();
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _getLoadedContent(bool usesImperialUnits, bool usesKj) {
    final s = S.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final energyUnitSuffix = usesKj ? s.kjLabel : s.kcalLabel;
    // Packaging prints nutrition in metric, so the basis is metric whatever
    // the size fields are shown in.
    final basisUnit = selectedUnit == 'ml' ? s.milliliterUnit : s.gramUnit;
    final sizeUnit = _sizeUnitSuffix(context);
    Widget sectionTitle(String text) => Text(
      text,
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    InputDecoration decoration(String label, {String? helper}) =>
        InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
        );
    Widget numberField(
      TextEditingController controller,
      String identifier,
      String label, {
      String? helper,
    }) => Semantics(
      identifier: identifier,
      child: TextFormField(
        controller: controller,
        inputFormatters: CustomTextInputFormatter.doubleOnly(),
        decoration: decoration(label, helper: helper),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(Dimens.spacing16),
      children: [
        // Custom meals get the same picker tile recipes use — a single
        // tappable circle with an overlay camera icon, "Add a photo"
        // text beneath, and a bottom-sheet for the action choice.
        // OFF / FDC entries keep the existing remote-image avatar:
        // they cannot have a user-attached photo, so showing the
        // picker affordance would be misleading.
        if (_mealEntity.source == MealSourceEntity.custom)
          Center(
            child: UserImagePickerTile(
              kind: UserImageKind.meal,
              imagePath: _localImagePath,
              onPickFromGallery: () => _onPickMealImage(ImageSource.gallery),
              onTakePhoto: () => _onPickMealImage(ImageSource.camera),
              onRemove: _onRemoveMealImage,
            ),
          )
        else
          Center(child: _buildRemoteMealImage()),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameTextController,
          decoration: decoration(s.mealNameLabel),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: Dimens.spacing24),
        sectionTitle(s.editFoodNutritionTitle),
        const SizedBox(height: Dimens.spacing4),
        Text(
          s.editFoodNutritionHint,
          style: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: Dimens.spacing16),
        // Unit first: every quantity below is entered in it (#495).
        Semantics(
          identifier: 'edit-meal-unit-selector',
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: _units[0], label: Text(s.editFoodUnitSolid)),
              ButtonSegment(
                value: _units[1],
                label: Text(s.editFoodUnitLiquid),
              ),
            ],
            selected: {selectedUnit},
            onSelectionChanged: (selection) =>
                setState(() => selectedUnit = selection.first),
          ),
        ),
        const SizedBox(height: Dimens.spacing12),
        Semantics(
          identifier: 'edit-meal-nutrients-mode',
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(s.mealNutrientsPerQtyLabel('100', basisUnit)),
              ),
              ButtonSegment(value: false, label: Text(s.editFoodBasisOther)),
            ],
            selected: {_per100},
            onSelectionChanged: (selection) =>
                setState(() => _per100 = selection.first),
          ),
        ),
        const SizedBox(height: Dimens.spacing16),
        if (!_per100) ...[
          numberField(
            _baseQuantityTextController,
            'edit-meal-basis-weight',
            '${s.editFoodBasisWeightLabel} ($basisUnit)',
            helper: s.editFoodBasisWeightHelper,
          ),
          const SizedBox(height: Dimens.spacing16),
        ],
        numberField(
          _kcalTextController,
          'edit-meal-energy',
          '${s.mealEnergyLabel} ($energyUnitSuffix)',
        ),
        const SizedBox(height: Dimens.spacing12),
        numberField(
          _carbsTextController,
          'edit-meal-carbs',
          '${s.mealCarbsLabel} (${s.gramUnit})',
        ),
        const SizedBox(height: Dimens.spacing12),
        numberField(
          _fatTextController,
          'edit-meal-fat',
          '${s.mealFatLabel} (${s.gramUnit})',
        ),
        const SizedBox(height: Dimens.spacing12),
        numberField(
          _proteinTextController,
          'edit-meal-protein',
          '${s.mealProteinLabel} (${s.gramUnit})',
        ),
        const SizedBox(height: Dimens.spacing16),
        ListenableBuilder(
          listenable: Listenable.merge([
            _baseQuantityTextController,
            _kcalTextController,
            _carbsTextController,
            _fatTextController,
            _proteinTextController,
            _mealQuantityTextController,
            _servingQuantityTextController,
          ]),
          builder: (context, _) =>
              _buildSavedSummary(context, energyUnitSuffix, basisUnit),
        ),
        const SizedBox(height: Dimens.spacing32),
        sectionTitle(s.editFoodSizesTitle),
        const SizedBox(height: Dimens.spacing16),
        numberField(
          _mealQuantityTextController,
          'edit-meal-pack-size',
          '${s.editFoodPackLabel} ($sizeUnit)',
          helper: s.editFoodPackHelper,
        ),
        const SizedBox(height: Dimens.spacing12),
        numberField(
          _servingQuantityTextController,
          'edit-meal-serving-size',
          '${s.editFoodServingLabel} ($sizeUnit)',
          helper: s.editFoodServingHelper,
        ),
        const SizedBox(height: Dimens.spacing24),
        TextFormField(
          controller: _brandsTextController,
          decoration: decoration(s.mealBrandsLabel),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: Dimens.spacing12),
        // Optional barcode (#167). Lets the user attach a code to a custom
        // meal so a future scan recalls the saved version directly without
        // round-tripping through Open Food Facts.
        Semantics(
          identifier: 'edit-meal-barcode-input',
          child: TextFormField(
            controller: _barcodeTextController,
            decoration: InputDecoration(
              labelText: s.customMealBarcodeLabel,
              hintText: s.customMealBarcodeHint,
              border: const OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
              ),
              suffixIcon: Semantics(
                identifier: 'edit-meal-barcode-scan',
                child: IconButton(
                  tooltip: s.customMealBarcodeScanButton,
                  icon: const Icon(Icons.barcode_reader),
                  onPressed: _scanBarcodeIntoField,
                ),
              ),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: Dimens.spacing12),
        // Rarely filled in by hand, so folded away. They are read on the same
        // basis as the values above.
        ExpansionTile(
          title: Text(s.editFoodMoreNutrientsLabel),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: Dimens.spacing8),
          shape: const Border(),
          collapsedShape: const Border(),
          maintainState: true,
          children: [
            for (final (controller, label, unit) in [
              (_fiberTextController, s.fiberLabel, 'g'),
              (_saturatedFatTextController, s.saturatedFatLabel, 'g'),
              (_sugarsTextController, s.sugarLabel, 'g'),
              (_sodiumTextController, s.sodiumLabel, 'mg'),
              (_calciumTextController, s.calciumLabel, 'mg'),
              (_ironTextController, s.ironLabel, 'mg'),
              (_potassiumTextController, s.potassiumLabel, 'mg'),
              (_magnesiumTextController, s.magnesiumLabel, 'mg'),
              (_vitaminDTextController, s.vitaminDLabel, 'µg'),
              (_vitaminB12TextController, s.vitaminB12Label, 'µg'),
            ]) ...[
              _buildMicroField(controller, label, unit),
              const SizedBox(height: Dimens.spacing12),
            ],
          ],
        ),
        if (!_editOnly && !_pickMode) ...[
          const SizedBox(height: Dimens.spacing16),
          _SaveForLaterField(
            value: _saveForLater,
            onChanged: (newValue) {
              setState(() {
                _saveForLater = newValue;
              });
            },
          ),
        ],
      ],
    );
  }

  /// The weight the typed nutrition values are for, or null while "other
  /// weight" is chosen and no usable weight is typed.
  double? get _basisQuantity {
    if (_per100) return 100;
    final typed = double.tryParse(_baseQuantityTextController.text);
    return typed != null && typed.isFinite && typed > 0 ? typed : null;
  }

  /// A size field in grams or millilitres, or null when empty or zero.
  double? _metricSize(TextEditingController controller) {
    if (controller.text.trim().isEmpty) return null;
    final text = _usesImperialUnits
        ? _convertToMetric(controller.text, selectedUnit)
        : controller.text;
    final value = double.tryParse(text);
    return value != null && value > 0 ? value : null;
  }

  Widget _buildSavedSummary(
    BuildContext context,
    String energyUnit,
    String basisUnit,
  ) {
    final s = S.of(context);
    final basis = _basisQuantity;
    double? per100(TextEditingController controller) {
      final value = double.tryParse(controller.text);
      return value == null || basis == null ? null : value * 100 / basis;
    }

    final energy = per100(_kcalTextController);
    final String? placeholder = basis == null
        ? s.editFoodSummaryNeedsWeight
        : (energy == null ? s.editFoodSummaryEmpty : null);
    String sized(double value) =>
        '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $basisUnit';

    final pack = _metricSize(_mealQuantityTextController);
    final serving = _metricSize(_servingQuantityTextController);
    return SavedNutritionCard(
      energyPer100: energy,
      carbsPer100: per100(_carbsTextController),
      fatPer100: per100(_fatTextController),
      proteinPer100: per100(_proteinTextController),
      energyUnit: energyUnit,
      placeholder: placeholder,
      amounts: [
        (title: sized(100), grams: 100),
        if (pack != null && pack != 100)
          (title: s.editFoodSummaryPack(sized(pack)), grams: pack),
        if (serving != null && serving != 100)
          (title: s.editFoodSummaryServing(sized(serving)), grams: serving),
      ],
    );
  }

  Widget _buildMicroField(
    TextEditingController controller,
    String label,
    String unit,
  ) {
    return TextFormField(
      controller: controller,
      inputFormatters: CustomTextInputFormatter.doubleOnly(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }

  /// Returns "0" for empty / whitespace-only text, otherwise the original
  /// string. A custom food's blank macro is stored as an explicit 0: the user
  /// is the source of truth for it, many foods have none of one macro, and a
  /// null there would make the product screen refuse to log the food (#232).
  String _zeroIfBlank(String text) {
    return text.trim().isEmpty ? '0' : text;
  }

  /// The unit of the pack and serving fields. It follows the g/ml switch and
  /// the user's metric/imperial setting (#495).
  String _sizeUnitSuffix(BuildContext context) {
    final s = S.of(context);
    if (selectedUnit == 'ml') {
      return _usesImperialUnits ? s.flOzUnit : s.milliliterUnit;
    }
    return _usesImperialUnits ? s.ozUnit : s.gramUnit;
  }

  /// Set while a save runs, so a second tap on Save before the first one has
  /// navigated away does nothing. A second run would build the meal again
  /// from the same pre-edit [_mealEntity]: after a barcode clear that is a
  /// fresh internal id matching no entry, and the library got a copy.
  bool _saving = false;

  Future<void> _onSavePressed(bool usesImperialUnits) async {
    if (_saving) return;
    _saving = true;
    try {
      await _save(usesImperialUnits);
    } finally {
      _saving = false;
    }
  }

  Future<void> _save(bool usesImperialUnits) async {
    try {
      // Validate meal name: non-empty and contains at least one letter (#211, #214)
      if (!FoodNameValidator.isValid(_nameTextController.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).mealNameValidationError)));
        return;
      }

      // Validate barcode shape if the user typed or scanned one (#167).
      // Empty is fine — the field is optional. 8-14 digits required;
      // EAN-13 check digit must verify for codes of that exact length.
      final rawBarcode = _barcodeTextController.text.trim();
      if (rawBarcode.isNotEmpty) {
        if (!isBarcodeFormatValid(rawBarcode)) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context).customMealBarcodeInvalid)));
          return;
        }
        if (!isEan13CheckDigitValid(rawBarcode)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(S.of(context).barcodeInvalidEan13CheckDigit)));
          return;
        }
      }

      final isCustom = _mealEntity.source == MealSourceEntity.custom;
      final basisQuantity = _basisQuantity;
      if (basisQuantity == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).editFoodSummaryNeedsWeight)),
        );
        return;
      }

      // The energy field is rendered in the user's active unit (#177
      // follow-up). Parse it as that unit and immediately fold it back to
      // kcal: every check and every persisted value expects kcal.
      final usesKjOnSave = Provider.of<EnergyUnitProvider>(
        context,
        listen: false,
      ).usesKilojoules;
      final enteredEnergyRaw = double.tryParse(_kcalTextController.text);
      final enteredKcal = enteredEnergyRaw == null
          ? null
          : (usesKjOnSave
                ? double.parse(
                    UnitCalc.kjToKcal(enteredEnergyRaw).toStringAsFixed(1),
                  )
                : enteredEnergyRaw);
      final enteredCarbs = double.tryParse(_carbsTextController.text);
      final enteredFat = double.tryParse(_fatTextController.text);
      final enteredProtein = double.tryParse(_proteinTextController.text);

      // Nutritional consistency (#213), only for numbers the user changed: a
      // rename must not be blocked by figures a product arrived with.
      if (_nutritionTexts() != _initialNutritionTexts || !_per100) {
        final macroTotal =
            (enteredCarbs ?? 0) + (enteredFat ?? 0) + (enteredProtein ?? 0);
        if (macroTotal > basisQuantity * 1.05) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                S
                    .of(context)
                    .editMealMacrosExceedBaseQuantityLabel(
                      macroTotal.toStringAsFixed(1),
                      basisQuantity.toStringAsFixed(0),
                    ),
              ),
            ),
          );
          return;
        }

        if (enteredKcal != null && enteredKcal > basisQuantity * 9) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                S
                    .of(context)
                    .editMealKcalTooHighLabel(basisQuantity.toStringAsFixed(0)),
              ),
            ),
          );
          return;
        }

        // Atwater check (#213): warn, without blocking, when the energy is
        // more than 5% away from 4·carbs + 4·protein + 9·fat.
        if (enteredKcal != null &&
            enteredCarbs != null &&
            enteredFat != null &&
            enteredProtein != null) {
          final expectedKcal =
              4 * enteredCarbs + 4 * enteredProtein + 9 * enteredFat;
          final delta = (enteredKcal - expectedKcal).abs();
          final ceiling = math.max(enteredKcal.abs(), expectedKcal.abs());
          if (ceiling > 0 && delta > 0.05 * ceiling) {
            final shouldSaveAnyway = await _showAtwaterWarningDialog();
            if (!mounted) return;
            if (shouldSaveAnyway != true) {
              return;
            }
          }
        }
      }

      // The size fields are loaded and edited in imperial too (see the
      // initial _convertToImperial above), so they fold back to metric (#495).
      String metricText(TextEditingController controller) {
        final text = controller.text;
        return usesImperialUnits && text.trim().isNotEmpty
            ? _convertToMetric(text, selectedUnit)
            : text;
      }

      // `createNewMealEntity` scales everything from the basis to per 100.
      String nutritionText(String text) => isCustom ? _zeroIfBlank(text) : text;

      // A micronutrient nobody typed keeps its stored per-100 value, whatever
      // basis was chosen for the numbers typed above it.
      final factor = factorTo100gFromBase('$basisQuantity');
      String microText(TextEditingController controller, double? stored) {
        final untouched = controller.text == _initialMicroTexts[controller];
        if (stored != null && (untouched || controller.text.trim().isEmpty)) {
          return '${stored / factor}';
        }
        return controller.text;
      }

      final stored = _mealEntity.nutriments;
      final MealEntity newMealEntity = _editMealBloc.createNewMealEntity(
        _mealEntity,
        _nameTextController.text,
        _brandsTextController.text,
        metricText(_mealQuantityTextController),
        metricText(_servingQuantityTextController),
        '$basisQuantity',
        selectedUnit,
        nutritionText(
          enteredKcal == null
              ? _kcalTextController.text
              : enteredKcal.toStringOrEmpty(),
        ),
        nutritionText(_carbsTextController.text),
        nutritionText(_fatTextController.text),
        nutritionText(_proteinTextController.text),
        fiberText: microText(_fiberTextController, stored.fiber100),
        saturatedFatText: microText(
          _saturatedFatTextController,
          stored.saturatedFat100,
        ),
        sugarsText: microText(_sugarsTextController, stored.sugars100),
        sodiumText: microText(_sodiumTextController, stored.sodium100),
        calciumText: microText(_calciumTextController, stored.calcium100),
        ironText: microText(_ironTextController, stored.iron100),
        potassiumText: microText(_potassiumTextController, stored.potassium100),
        magnesiumText: microText(_magnesiumTextController, stored.magnesium100),
        vitaminDText: microText(_vitaminDTextController, stored.vitaminD100),
        vitaminB12Text: microText(
          _vitaminB12TextController,
          stored.vitaminB12100,
        ),
        barcodeOverride: rawBarcode,
        localImagePathOverride: _localImagePath,
        clearLocalImagePath: _localImageCleared && _localImagePath == null,
      );

      // Persist custom meal template (#267). Skipped for one-off entries
      // (#249) when the user has turned off "Save for next time" — the
      // intake itself is still logged below, but no template is kept.
      final shouldPersistTemplate = _editOnly || _pickMode || _saveForLater;
      if (newMealEntity.source == MealSourceEntity.custom &&
          shouldPersistTemplate) {
        await _editMealBloc.saveCustomMeal(
          newMealEntity,
          previous: _mealEntity,
        );
      }

      if (!mounted) return;
      if (_pickMode) {
        // Created for a recipe: hand the food back to the picker that asked.
        Navigator.of(context).pop(newMealEntity);
      } else if (_editOnly) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(
          NavigationOptions.mealDetailRoute,
          namedRouteOrFirst(NavigationOptions.addMealRoute),
          arguments: MealDetailScreenArguments(
            newMealEntity,
            _intakeTypeEntity,
            _day,
            usesImperialUnits,
            logTray: _logTray,
          ),
        );
      }
    } catch (exception, stacktrace) {
      log.warning("Error while creating new meal entity");
      Sentry.captureException(exception, stackTrace: stacktrace);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.of(context).errorMealSave)));
    }
  }

  /// Push a lightweight `MobileScanner` page that returns the first product
  /// barcode it sees, then drop the value into the barcode TextField. The
  /// scan-time validator on the field handles bad codes (8–14 digits,
  /// EAN-13 check digit) — we don't double-validate here so the user can
  /// see and edit the raw scanned value before saving.
  Future<void> _scanBarcodeIntoField() async {
    log.fine('Opening edit-meal barcode scanner');
    final navigator = Navigator.of(context);
    final result = await navigator.push<String?>(
      MaterialPageRoute(builder: (_) => const _EditMealBarcodeScanPage()),
    );
    log.fine('Edit-meal barcode scanner returned: $result');
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _barcodeTextController.text = result;
    });
    log.fine('Barcode text controller after set: ${_barcodeTextController.text}');
  }

  Widget _buildRemoteMealImage() {
    return ClipOval(
      child: CachedNetworkImage(
        cacheManager: locator<CacheManager>(),
        width: 120,
        height: 120,
        placeholder: (context, string) => const DefaultMealImage(),
        errorWidget: (context, exception, stacktrace) =>
            const DefaultMealImage(),
        fit: BoxFit.cover,
        imageUrl: _mealEntity.mainImageUrl ?? "",
      ),
    );
  }

  Future<void> _onPickMealImage(ImageSource source) async {
    // For custom meals the entity's `code` is a stable UUID seeded at
    // MealEntity.empty() time; we use it as the photo's filename so a
    // re-edit of the same meal lands at the same on-disk slug. If the
    // user has typed a real barcode into the code field, fall back to
    // the entity's original code rather than the in-progress text — the
    // photo identity is the meal, not the barcode.
    final ownerId = _mealEntity.code;
    if (ownerId == null) return;
    try {
      final picked = await UserImageStorage.pick(source);
      if (picked == null) return;
      final relative = await UserImageStorage.importPicked(
        kind: UserImageKind.meal,
        ownerId: ownerId,
        picked: picked,
      );
      if (!mounted) return;
      setState(() {
        _localImagePath = relative;
        _localImageCleared = false;
      });
    } catch (e, st) {
      // Pick / encode failure is rare; surfacing a SnackBar from inside
      // the picker flow felt noisier than the failure deserves. The user
      // can simply tap the picker again.
      log.warning('Failed to pick meal image', e, st);
    }
  }

  Future<void> _onRemoveMealImage() async {
    final current = _localImagePath;
    if (current == null) return;
    await UserImageStorage.delete(current);
    if (!mounted) return;
    setState(() {
      _localImagePath = null;
      _localImageCleared = true;
    });
  }

  Future<bool?> _showAtwaterWarningDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).inconsistentNutritionWarningTitle),
          content: Text(S.of(dialogContext).inconsistentNutritionWarningBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).inconsistentNutritionWarningEdit),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                S.of(dialogContext).inconsistentNutritionWarningSaveAnyway,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Grams unless the food is measured by volume, including the older
  /// "g/ml" foods, which no longer have a button of their own.
  String _switchButtonUnit(String? unit) =>
      MealEntity.liquidUnits.contains(unit) ? _units[1] : _units[0];

  String _convertToImperial(String value, String unit) {
    final double quantityValue = double.tryParse(value) ?? 0.0;
    switch (unit) {
      case 'g':
        return (UnitCalc.gToOz(quantityValue)).toStringAsFixed(2);
      case 'ml':
        return (UnitCalc.mlToFlOz(quantityValue)).toStringAsFixed(2);
      default:
        return value;
    }
  }

  String _convertToMetric(String value, String unit) {
    final double quantityValue = double.tryParse(value) ?? 0.0;
    switch (unit) {
      case 'g':
        return (UnitCalc.ozToG(quantityValue)).toStringAsFixed(2);
      case 'ml':
        return (UnitCalc.flOzToMl(quantityValue)).toStringAsFixed(2);
      default:
        return value;
    }
  }
}

class EditMealScreenArguments {
  final DateTime day;
  final MealEntity mealEntity;
  final IntakeTypeEntity intakeTypeEntity;
  final bool usesImperialUnits;
  final bool editOnly;

  /// Create a food and pop it back to the caller instead of opening the
  /// detail screen. The food is always kept for next time. Used by the recipe
  /// ingredient picker.
  final bool pickMode;

  /// The add-food screen's "To log" list, handed on to the detail screen a
  /// new food opens in so that it adds there instead of logging.
  final LogTray? logTray;

  EditMealScreenArguments(
    this.day,
    this.mealEntity,
    this.intakeTypeEntity,
    this.usesImperialUnits, {
    this.editOnly = false,
    this.pickMode = false,
    this.logTray,
  });

  /// A new, empty food whose result goes back to the caller; the day and
  /// meal type are never used on this path.
  EditMealScreenArguments.pick({required this.usesImperialUnits})
      : day = DateTime.now(),
        mealEntity = MealEntity.empty(),
        intakeTypeEntity = IntakeTypeEntity.snack,
        editOnly = false,
        pickMode = true,
        logTray = null;
}

/// "Save for next time" toggle shown on the create-and-log path (#249).
/// Defaults to off: the intake is logged today, and the user opts in here
/// to also keep the meal as a reusable template in the custom-meal list.
/// Leaving it off is the right call for one-off entries like a friend's
/// homemade dish or a restaurant meal that won't come back round.
class _SaveForLaterField extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SaveForLaterField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return AppCard(
      color: palette.surfaceMuted,
      onTap: () => onChanged(!value),
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing16,
        Dimens.spacing12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            identifier: 'edit-meal-save-for-later',
            child: Checkbox(
              value: value,
              onChanged: (newValue) => onChanged(newValue ?? false),
            ),
          ),
          const SizedBox(width: Dimens.spacing4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.recipeSaveForLaterLabel,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Dimens.spacing4),
                  Text(
                    s.recipeSaveForLaterDescription,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal camera page used by [_EditMealScreenState._scanBarcodeIntoField].
/// Pops itself with the first product barcode it detects, or returns null
/// when the user taps the back button. We keep this private to the edit-meal
/// flow rather than reusing the full ScannerScreen because that screen runs
/// its own lookup-and-route logic that wouldn't fit a "give me the raw
/// string" use case.
class _EditMealBarcodeScanPage extends StatefulWidget {
  const _EditMealBarcodeScanPage();

  @override
  State<_EditMealBarcodeScanPage> createState() =>
      _EditMealBarcodeScanPageState();
}

class _EditMealBarcodeScanPageState extends State<_EditMealBarcodeScanPage>
    with WidgetsBindingObserver {
  static final _log = Logger('EditMealBarcodeScan');
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_controller.stop());
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    _log.fine('onDetect: ${capture.barcodes.length} barcodes; '
        'types=${capture.barcodes.map((b) => b.type.name).toList()}; '
        'rawValues=${capture.barcodes.map((b) => b.rawValue).toList()}');
    if (_done) return;
    for (final b in capture.barcodes) {
      // Accept any non-null raw value. ML Kit's type classifier is reliable
      // for QR / data-matrix but sometimes labels a valid retail barcode as
      // `BarcodeType.unknown` depending on print quality and camera angle —
      // filtering strictly by `BarcodeType.product` was silently dropping
      // those. The save-time validator on the edit-meal screen does the
      // real "is this a valid barcode" check.
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _log.fine('Popping with rawValue=$raw (type=${b.type.name})');
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).customMealBarcodeScanButton)),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
