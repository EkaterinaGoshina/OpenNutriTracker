import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Grams of a macro as the meal header and the entry dialog show them: whole
/// numbers, one decimal under 10 g so a spoon of something does not read as
/// "0". A dash when there is no figure, which is not the same as zero.
String formatMacroGrams(BuildContext context, double? grams) {
  if (grams == null) return '—';
  final format = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toString(),
  )..maximumFractionDigits = grams < 10 ? 1 : 0;
  return format.format(grams);
}
