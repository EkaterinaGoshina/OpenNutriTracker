import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

class IngredientQuantitySelection {
  final double amount;
  final String unit;
  // Only for the 'pcs' unit: what one piece weighs, in grams.
  final double? pieceWeightG;
  const IngredientQuantitySelection({
    required this.amount,
    required this.unit,
    this.pieceWeightG,
  });
}

/// Unit as shown to the user. The stored value stays a stable key; only
/// 'pcs' and 'pinch' have a translated label, the rest read the same everywhere.
String ingredientUnitLabel(BuildContext context, String unit) {
  switch (unit) {
    case 'pcs':
      return S.of(context).recipeUnitPiece;
    case 'pinch':
      return S.of(context).recipeUnitPinch;
    default:
      return unit;
  }
}

/// Modal bottom sheet that asks for the amount + unit of an ingredient.
/// Returns an [IngredientQuantitySelection] or null if cancelled.
Future<IngredientQuantitySelection?> showIngredientQuantityDialog(
  BuildContext context, {
  required MealEntity meal,
  double? initialAmount,
  String? initialUnit,
  double? initialPieceWeightG,
}) {
  return showModalBottomSheet<IngredientQuantitySelection>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _IngredientQuantitySheet(
      meal: meal,
      initialAmount: initialAmount,
      initialUnit: initialUnit,
      initialPieceWeightG: initialPieceWeightG,
    ),
  );
}

class _IngredientQuantitySheet extends StatefulWidget {
  final MealEntity meal;
  final double? initialAmount;
  final String? initialUnit;
  final double? initialPieceWeightG;

  const _IngredientQuantitySheet({
    required this.meal,
    this.initialAmount,
    this.initialUnit,
    this.initialPieceWeightG,
  });

  @override
  State<_IngredientQuantitySheet> createState() =>
      _IngredientQuantitySheetState();
}

class _IngredientQuantitySheetState extends State<_IngredientQuantitySheet> {
  late TextEditingController _amountController;
  late TextEditingController _pieceWeightController;
  late String _unit;
  bool _pieceWeightMissing = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount != null
          ? widget.initialAmount!.toString()
          : '',
    );
    _unit = widget.initialUnit ?? _defaultUnit(widget.meal);
    final pieceWeight =
        widget.initialPieceWeightG ?? _guessPieceWeightG(widget.meal);
    _pieceWeightController = TextEditingController(
      text: pieceWeight == null ? '' : _formatGrams(pieceWeight),
    );
  }

  // A serving of a food is the best guess for one piece; an egg is the common
  // case that usually has no serving data, so it gets a typical weight.
  double? _guessPieceWeightG(MealEntity meal) {
    final serving = meal.scalableServingQuantity;
    if (serving != null && serving > 0) return serving;
    final name = (meal.name ?? '').toLowerCase();
    if (name.contains('яйц') || name.contains('яиц') || name.contains('egg')) {
      return 55;
    }
    return null;
  }

  String _formatGrams(double g) {
    final rounded = double.parse(g.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _pieceWeightController.dispose();
    super.dispose();
  }

  // Weight first, even for a food that has a serving: an ingredient is
  // measured out, and "150" read as 150 servings is a silent mistake. The
  // serving stays one tap away in the dropdown.
  String _defaultUnit(MealEntity meal) => meal.isLiquid ? 'ml' : 'g';

  List<DropdownMenuItem<String>> _unitItems(BuildContext context) {
    final items = <DropdownMenuItem<String>>[];
    if (widget.meal.hasServingValues) {
      items.add(_unitItem('serving'));
    }
    if (widget.meal.isSolid ||
        (!widget.meal.isLiquid && !widget.meal.isSolid)) {
      items.add(_unitItem('g'));
      items.add(_unitItem('kg'));
      items.add(_unitItem('oz'));
    }
    if (widget.meal.isLiquid ||
        (!widget.meal.isLiquid && !widget.meal.isSolid)) {
      items.add(_unitItem('ml'));
      items.add(_unitItem('l'));
      items.add(_unitItem('fl.oz'));
    }
    // Counted and pinched ingredients (2 eggs, a pinch of salt) are not weighed.
    items.add(_unitItem('pcs'));
    items.add(_unitItem('pinch'));
    return items;
  }

  DropdownMenuItem<String> _unitItem(String unit) {
    return DropdownMenuItem(
      value: unit,
      child: Text(
        ingredientUnitLabel(context, unit),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final fieldBorder = OutlineInputBorder(
      borderRadius: Dimens.borderRadiusS,
      borderSide: BorderSide(color: palette.border, width: Dimens.hairline),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Dimens.spacing24, Dimens.spacing24, Dimens.spacing24, Dimens.spacing16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(Dimens.radiusXL),
            topRight: Radius.circular(Dimens.radiusXL),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing20),
            Text(
              widget.meal.name ?? '?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Dimens.spacing16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _amountController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+([.,]\d{0,2})?$'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: S.of(context).recipeIngredientAmountLabel,
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                    ),
                  ),
                ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    itemHeight: null,
                    initialValue: _unit,
                    borderRadius: Dimens.borderRadiusM,
                    decoration: InputDecoration(
                      labelText: S.of(context).recipeIngredientUnitLabel,
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                    ),
                    items: _unitItems(context),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _unit = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_unit == 'pcs') ...[
              const SizedBox(height: Dimens.spacing12),
              TextFormField(
                controller: _pieceWeightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+([.,]\d{0,2})?$'),
                  ),
                ],
                onChanged: (_) {
                  if (_pieceWeightMissing) {
                    setState(() => _pieceWeightMissing = false);
                  }
                },
                decoration: InputDecoration(
                  labelText: S.of(context).recipePieceWeightLabel,
                  errorText: _pieceWeightMissing ? '' : null,
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                ),
              ),
            ],
            const SizedBox(height: Dimens.spacing24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: Dimens.spacing16),
                  shape: Dimens.shapeM,
                ),
                onPressed: _onConfirm,
                child: Text(S.of(context).addLabel),
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
          ],
        ),
      ),
    );
  }

  void _onConfirm() {
    final raw = _amountController.text.replaceAll(',', '.');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      Navigator.of(context).pop();
      return;
    }
    double? pieceWeightG;
    if (_unit == 'pcs') {
      pieceWeightG =
          double.tryParse(_pieceWeightController.text.replaceAll(',', '.'));
      // Without a weight a piece counts as 0 g, a silent mistake: stay open.
      if (pieceWeightG == null || pieceWeightG <= 0) {
        setState(() => _pieceWeightMissing = true);
        return;
      }
    }
    Navigator.of(context).pop(
      IngredientQuantitySelection(
        amount: amount,
        unit: _unit,
        pieceWeightG: pieceWeightG,
      ),
    );
  }
}
