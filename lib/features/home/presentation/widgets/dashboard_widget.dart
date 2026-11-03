import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class DashboardWidget extends StatefulWidget {
  final double totalKcalDaily;
  final double totalKcalLeft;
  final double totalKcalSupplied;
  final double totalKcalBurned;
  final double totalCarbsIntake;
  final double totalFatsIntake;
  final double totalProteinsIntake;
  final double totalCarbsGoal;
  final double totalFatsGoal;
  final double totalProteinsGoal;

  const DashboardWidget({
    super.key,
    required this.totalKcalSupplied,
    required this.totalKcalBurned,
    required this.totalKcalDaily,
    required this.totalKcalLeft,
    required this.totalCarbsIntake,
    required this.totalFatsIntake,
    required this.totalProteinsIntake,
    required this.totalCarbsGoal,
    required this.totalFatsGoal,
    required this.totalProteinsGoal,
  });

  @override
  State<DashboardWidget> createState() => _DashboardWidgetState();
}

class _DashboardWidgetState extends State<DashboardWidget> {
  void _openKcalGoalInfoScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const KcalGoalInfoScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double kcalValue = 0;
    double gaugeValue = 0;
    final usesKilojoules = context.watch<EnergyUnitProvider>().usesKilojoules;
    String kcalLabelText = usesKilojoules
        ? '${S.of(context).kjLabel} ${S.of(context).energyLeftLabel}'
        : S.of(context).kcalLeftLabel;

    if (widget.totalKcalLeft > widget.totalKcalDaily) {
      kcalValue = widget.totalKcalDaily;
      gaugeValue = 0;
    } else if (widget.totalKcalLeft < 0) {
      kcalValue = widget.totalKcalLeft.abs();
      gaugeValue = 1;
      kcalLabelText = usesKilojoules
          ? '${S.of(context).kjLabel} ${S.of(context).energyTooMuchLabel}'
          : S.of(context).kcalTooMuchLabel;
    } else {
      kcalValue = widget.totalKcalLeft;
      gaugeValue =
          (widget.totalKcalDaily - widget.totalKcalLeft) / widget.totalKcalDaily;
    }
    final displayValue = usesKilojoules ? UnitCalc.kcalToKj(kcalValue) : kcalValue;
    final displaySupplied = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalSupplied)
        : widget.totalKcalSupplied;
    final displayGoal = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalDaily)
        : widget.totalKcalDaily;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    final progressColor = widget.totalKcalLeft < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Dimens.spacing16, Dimens.spacing8, Dimens.spacing16, Dimens.spacing4),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(Dimens.spacing24, Dimens.spacing20, Dimens.spacing24, Dimens.spacing24),
            child: Column(
              children: [
                Semantics(
                  identifier: 'home-kcal-gauge',
                  label: '${displayValue.round()} $kcalLabelText',
                  hint: S.of(context).settingsKcalGoalInfoLabel,
                  button: true,
                  excludeSemantics: true,
                  // excludeSemantics strips the GestureDetector's semantic
                  // tap action along with the rest of the subtree, so the
                  // node needs its own onTap for screen readers to be able
                  // to activate the button it announces.
                  onTap: _openKcalGoalInfoScreen,
                  // Tapping the gauge opens the calorie-goal transparency
                  // screen, so the central number on the dashboard is one
                  // tap away from its full derivation.
                  child: Tooltip(
                    message: S.of(context).settingsKcalGoalInfoLabel,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openKcalGoalInfoScreen,
                      child: CircularPercentIndicator(
                        radius: 72,
                        lineWidth: 14,
                        percent: gaugeValue.clamp(0.0, 1.0),
                        animation: true,
                        // The dashboard's first-ever build of a session (a
                        // cold start, or landing on Home right after
                        // seeding/onboarding) must show the real value
                        // immediately — animating up from 0% every time
                        // reads as the data being wrong for a beat, not as
                        // a nice reveal. Later rebuilds (e.g. logging a
                        // meal) still animate from the old percent, since
                        // that's a real, visible change worth animating.
                        animateToInitialPercent: false,
                        animationDuration: 800,
                        curve: AppMotion.emphasized,
                        circularStrokeCap: CircularStrokeCap.round,
                        backgroundColor: palette.surfaceMuted,
                        progressColor: progressColor,
                        center: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedFlipCounter(
                              duration: const Duration(milliseconds: 800),
                              curve: AppMotion.emphasized,
                              value: displayValue.round(),
                              textStyle: textTheme.displaySmall?.copyWith(height: 1),
                            ),
                            const SizedBox(height: 2),
                            Text(kcalLabelText, style: textTheme.bodyMedium?.copyWith(color: palette.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Dimens.spacing16),
                Text(
                  S.of(context).dashboardEatenOfGoal(
                    displaySupplied.round(),
                    displayGoal.round(),
                    usesKilojoules ? S.of(context).kjLabel : S.of(context).kcalLabel,
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                // Macros share the calorie card: one summary surface for the
                // day instead of a card per nutrient.
                const SizedBox(height: Dimens.spacing24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MacroColumn(
                        label: S.of(context).carbsLabel,
                        intake: widget.totalCarbsIntake,
                        goal: widget.totalCarbsGoal,
                        color: palette.carbs,
                        palette: palette,
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing16),
                    Expanded(
                      child: _MacroColumn(
                        label: S.of(context).fatLabel,
                        intake: widget.totalFatsIntake,
                        goal: widget.totalFatsGoal,
                        color: palette.fat,
                        palette: palette,
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing16),
                    Expanded(
                      child: _MacroColumn(
                        label: S.of(context).proteinLabel,
                        intake: widget.totalProteinsIntake,
                        goal: widget.totalProteinsGoal,
                        color: palette.protein,
                        palette: palette,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroColumn extends StatelessWidget {
  final String label;
  final double intake;
  final double goal;
  final Color color;
  final AppPalette palette;

  const _MacroColumn({
    required this.label,
    required this.intake,
    required this.goal,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pct = (goal <= 0) ? 0.0 : (intake / goal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: textTheme.labelMedium)),
          ],
        ),
        const SizedBox(height: Dimens.spacing8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: palette.surfaceMuted,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Text(
          '${intake.toInt()}/${goal.toInt()} ${S.of(context).gramUnit}',
          style: textTheme.bodySmall?.copyWith(color: palette.textStrong, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
