import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show toBeginningOfSentenceCase;
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/macro_grams.dart';
import 'package:opennutritracker/generated/l10n.dart';

class EditDialog extends StatefulWidget {
  final IntakeEntity intakeEntity;
  final bool usesImperialUnits;

  const EditDialog({
    super.key,
    required this.intakeEntity,
    required this.usesImperialUnits,
  });

  @override
  State<StatefulWidget> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late TextEditingController amountEditingController;

  @override
  void initState() {
    super.initState();
    double initialAmount = _convertValue(
      widget.intakeEntity.amount,
      widget.intakeEntity.meal.mealUnit,
    );
    amountEditingController = TextEditingController(
      text: initialAmount.toStringAsFixed(2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).editItemDialogTitle),
      // Scrolls: with the keyboard up a small phone has no room for it all.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.intakeEntity.meal.name ?? '?',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            // Room for the field's label, which rises above its box.
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'edit-intake-amount',
              child: TextFormField(
                controller: amountEditingController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: CustomTextInputFormatter.doubleOnly(),
                decoration: InputDecoration(
                  labelText: S.of(context).quantityLabel,
                  suffixText: _convertUnit(
                    widget.intakeEntity.meal.mealUnit ?? '',
                  ),
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            // Follows the field, so the new portion is seen before OK.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: amountEditingController,
              builder: (context, value, _) => _buildNutrition(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final newAmount = _enteredAmount();
            if (newAmount == null) return;
            Navigator.of(context).pop(newAmount);
          },
          child: Text(S.of(context).dialogOKLabel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(S.of(context).dialogCancelLabel),
        ),
      ],
    );
  }

  /// The amount in the field in the entry's metric unit, null while the field
  /// does not hold a number.
  double? _enteredAmount() {
    final typed = double.tryParse(
      amountEditingController.text.replaceAll(',', '.'),
    );
    if (typed == null) return null;
    return _convertBackToMetricValue(typed, widget.intakeEntity.meal.mealUnit);
  }

  /// Energy, protein, fat and carbs of the amount in the field.
  Widget _buildNutrition(BuildContext context) {
    final s = S.of(context);
    final nutriments = widget.intakeEntity.meal.nutriments;
    final amount = _enteredAmount();
    double? inPortion(double? perUnit) =>
        amount == null || perUnit == null ? null : amount * perUnit;
    String grams(double? perUnit) {
      final value = inPortion(perUnit);
      final text = formatMacroGrams(context, value);
      return value == null ? text : '$text ${s.gramUnit}';
    }

    final kcal = inPortion(nutriments.energyPerUnit);
    return Column(
      children: [
        _nutritionRow(
          context,
          EnergyDisplay.unitLabel(context),
          kcal == null ? '—' : EnergyDisplay.formatValue(context, kcal),
        ),
        _nutritionRow(
          context,
          s.proteinLabel,
          grams(nutriments.proteinsPerUnit),
        ),
        _nutritionRow(context, s.fatLabel, grams(nutriments.fatPerUnit)),
        _nutritionRow(
          context,
          s.carbsLabel,
          grams(nutriments.carbohydratesPerUnit),
        ),
      ],
    );
  }

  Widget _nutritionRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing4),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Text(
                toBeginningOfSentenceCase(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _convertValue(double value, String? unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? UnitCalc.gToOz(value) : value;
      case 'ml':
        return widget.usesImperialUnits ? UnitCalc.mlToFlOz(value) : value;
      default:
        return value;
    }
  }

  double _convertBackToMetricValue(double value, String? unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? UnitCalc.ozToG(value) : value;
      case 'ml':
        return widget.usesImperialUnits ? UnitCalc.flOzToMl(value) : value;
      default:
        return value;
    }
  }

  String _convertUnit(String unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? 'oz' : 'g';
      case 'ml':
        return widget.usesImperialUnits ? 'fl.oz' : 'ml';
      default:
        return unit;
    }
  }
}
