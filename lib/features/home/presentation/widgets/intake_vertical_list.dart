import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/copy_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/copy_to_profile_sheet.dart';
import 'package:opennutritracker/core/presentation/widgets/delete_all_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_card.dart';
import 'package:opennutritracker/core/presentation/widgets/placeholder_card.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/macro_grams.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/tracked_day_lock.dart';
import 'package:opennutritracker/core/utils/vertical_list_popup_menu_selections.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_sort_type.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_meal_payload.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class IntakeVerticalList extends StatefulWidget {
  final DateTime day;
  final String title;
  final IconData listIcon;
  final AddMealType addMealType;
  final List<IntakeEntity> intakeList;
  final bool usesImperialUnits;
  final bool showMealMacros;
  final Function(IntakeEntity intake, TrackedDayEntity? trackedDayEntity)
  onDeleteIntakeCallback;
  final Function(BuildContext, IntakeEntity)? onItemLongPressedCallback;
  final Function(bool)? onItemDragCallback;
  final Function(BuildContext, IntakeEntity, bool)? onItemTappedCallback;
  final Function(IntakeEntity intake, TrackedDayEntity? trackedDayEntity,
      AddMealType? type)? onCopyIntakeCallback;
  final TrackedDayEntity? trackedDayEntity;
  // #150: optional recommended kcal target for this meal section. When
  // supplied and > 0, the section header shows "consumed / target kcal" so
  // someone scanning the day can see at a glance whether breakfast (or any
  // other meal) sat inside the share they had planned for it.
  final double? mealKcalTarget;

  /// Current sort applied to [intakeList]. When non-null (and
  /// [onSortTypeChanged] is also provided), a small sort menu is rendered in
  /// the section header. Callers are responsible for sorting [intakeList]
  /// before it reaches the widget — this field only drives the menu's
  /// highlighted selection.
  final DiarySortType? sortType;

  /// Called when the user picks a new sort option from the section header.
  /// When null, the sort menu is hidden.
  final ValueChanged<DiarySortType>? onSortTypeChanged;

  /// The section Home uses: one card holds the whole meal, with the totals
  /// under the title and the entries as rows below. The add button sits in
  /// the header instead of a full-width row under the entries, and the whole
  /// card is the drop target so an empty one still takes a meal.
  final bool compact;

  const IntakeVerticalList({
    super.key,
    required this.day,
    required this.title,
    required this.listIcon,
    required this.addMealType,
    required this.intakeList,
    required this.usesImperialUnits,
    this.showMealMacros = true,
    required this.onDeleteIntakeCallback,
    this.onItemLongPressedCallback,
    this.onItemDragCallback,
    this.onItemTappedCallback,
    this.onCopyIntakeCallback,
    this.trackedDayEntity,
    this.mealKcalTarget,
    this.sortType,
    this.onSortTypeChanged,
    this.compact = false,
  });

  /// Whether a meal section is rendered on Home and in the Diary. A 0 % share
  /// hides an empty section the user opted out of (OMAD, two-meal), but one
  /// that already holds intakes always shows: otherwise those entries count
  /// toward the day's totals with no way to see, edit or delete them (#1305).
  static bool isShown({
    required int sharePct,
    required List<IntakeEntity> intakes,
  }) =>
      sharePct > 0 || intakes.isNotEmpty;

  @override
  State<IntakeVerticalList> createState() => _IntakeVerticalListState();
}

class _IntakeVerticalListState extends State<IntakeVerticalList> {
  late MealDetailBloc _mealDetailBloc;
  late HomeBloc _homeBloc;

  @override
  void initState() {
    _mealDetailBloc = locator<MealDetailBloc>();
    _homeBloc = locator<HomeBloc>();
    super.initState();
  }

  double get totalKcal {
    return widget.intakeList
        .fold(0, (previousValue, element) => previousValue + element.totalKcal);
  }

  /// The meal's grams of one macro, from the entries that have a figure. Null
  /// when none of them does.
  double? _mealGrams(double? Function(MealNutrimentsEntity) perUnit) {
    double? total;
    for (final intake in widget.intakeList) {
      final value = perUnit(intake.meal.nutriments);
      if (value != null) total = (total ?? 0) + intake.amount * value;
    }
    return total;
  }

  /// "P 32 · F 18 · C 45" for the whole meal.
  String _buildMacroLine(BuildContext context) {
    final s = S.of(context);
    String part(String label, double? grams) =>
        '${label.toUpperCase()} ${formatMacroGrams(context, grams)}';
    return [
      part(s.proteinLabelShort, _mealGrams((n) => n.proteinsPerUnit)),
      part(s.fatLabelShort, _mealGrams((n) => n.fatPerUnit)),
      part(s.carbsLabelShort, _mealGrams((n) => n.carbohydratesPerUnit)),
    ].join(' · ');
  }

  // #150: only show a header when we have something to say — either some
  // food was logged, or a recommended target exists so the section can read
  // "0 / 600 kcal" before anything is logged.
  bool get _hasMealKcalTarget =>
      widget.mealKcalTarget != null && widget.mealKcalTarget! > 0;

  bool get _shouldShowHeaderSummary => totalKcal > 0 || _hasMealKcalTarget;

  String _buildHeaderSummary(BuildContext context) {
    if (!_hasMealKcalTarget) {
      return EnergyDisplay.formatWithUnit(context, totalKcal);
    }
    return S.of(context).diaryMealKcalConsumedOfTarget(
      EnergyDisplay.formatValue(context, totalKcal),
      EnergyDisplay.formatValue(context, widget.mealKcalTarget!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    final compact = widget.compact;
    final showsMacroLine =
        widget.showMealMacros && widget.intakeList.isNotEmpty;
    final section = Column(
      children: [
        Container(
          constraints: compact ? const BoxConstraints(minHeight: 72) : null,
          padding: compact
              ? const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing12,
                  Dimens.spacing4,
                  Dimens.spacing12,
                )
              : const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing20,
                  Dimens.spacing12,
                  Dimens.spacing8,
                ),
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Dimens.spacing8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: Dimens.borderRadiusS,
                    ),
                    child: Icon(widget.listIcon, size: 20, color: accent),
                  ),
                  const SizedBox(width: Dimens.spacing12),
                  if (compact)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle(textTheme, palette, FontWeight.w800),
                          if (_shouldShowHeaderSummary)
                            _buildGroupSummary(context, textTheme, palette),
                          if (showsMacroLine)
                            Text(
                              _buildMacroLine(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelMedium?.copyWith(
                                color: palette.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    )
                  else ...[
                    Expanded(
                      child: _buildTitle(textTheme, palette, FontWeight.w700),
                    ),
                    const SizedBox(width: Dimens.spacing8),
                    // Expanded, not Flexible: a loose Flexible shares the free
                    // space with the title but keeps only its text's width, so
                    // the kcal line and the buttons stopped at mid-row with a
                    // gap to the right.
                    if (_shouldShowHeaderSummary)
                      Expanded(
                        child: Text(
                          _buildHeaderSummary(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                  ],
                  if (widget.onSortTypeChanged != null && totalKcal > 0)
                    _buildSortMenu(context),
                  if (widget.compact)
                    Semantics(
                      identifier: 'add-meal-placeholder',
                      container: true,
                      child: IconButton(
                        tooltip: S.of(context).addLabel,
                        icon: Icon(Icons.add_rounded, color: accent),
                        onPressed: () => _onPlaceholderCardTapped(context),
                      ),
                    ),
                  // Every entry needs something to act on, so an empty section has
                  // no menu at all.
                  if (totalKcal > 0)
                    Semantics(
                      identifier: 'intake-section-menu',
                      // Tight bounds: without this the node inherits the flex
                      // Row's full-width box and coordinate taps miss the button.
                      container: true,
                      child: PopupMenuButton<VerticalListPopupMenuSelections>(
                        icon: Icon(Icons.more_vert_rounded, color: palette.textMuted),
                        shape: Dimens.shapeM,
                        onSelected:
                            (VerticalListPopupMenuSelections selection) async {
                          // The section as it was when the menu was used: the
                          // Diary can move on to another day while a dialog is
                          // open (#1360), rebuilding this list for that day.
                          final intakes = widget.intakeList;
                          final onDeleteIntake = widget.onDeleteIntakeCallback;
                          final trackedDay = widget.trackedDayEntity;
                          switch (selection) {
                            case VerticalListPopupMenuSelections.onCopy:
                              final copyDialog =
                                  CopyDialog(initialValue: widget.addMealType);
                              final selectedMealType =
                                  await showDialog<AddMealType>(
                                      context: context,
                                      builder: (context) => copyDialog);
                              if (selectedMealType != null) {
                                for (IntakeEntity intake in intakes) {
                                  widget.onCopyIntakeCallback!(
                                      intake, null, selectedMealType);
                                }
                              }
                              break;
                            case VerticalListPopupMenuSelections.onDelete:
                              final shouldDeleteIntakes = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => const DeleteAllDialog());
                              if (shouldDeleteIntakes != null) {
                                for (IntakeEntity intake in intakes) {
                                  onDeleteIntake(intake, trackedDay);
                                }
                                break;
                              }
                            case VerticalListPopupMenuSelections.onShare:
                              if (context.mounted) {
                                final code = SharedMealPayload.fromIntakeList(
                                  widget.intakeList,
                                  recipeRepository: locator<RecipeRepository>(),
                                ).toJsonString();
                                final hasOtherProfiles =
                                    locator<GetProfilesUsecase>()
                                            .getProfiles()
                                            .length >
                                        1;
                                await showDialog(
                                  context: context,
                                  builder: (_) => ShareQrDialog(
                                    title: S.of(context).shareMealLabel,
                                    code: code,
                                    fileBaseName: 'meal_qr',
                                    onCopyToProfile: hasOtherProfiles
                                        ? () => showCopyToProfileSheet(
                                              context,
                                              widget.intakeList,
                                            )
                                        : null,
                                  ),
                                );
                              }
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<VerticalListPopupMenuSelections>>[
                              if (widget.onCopyIntakeCallback != null &&
                                  totalKcal > 0)
                                PopupMenuItem<VerticalListPopupMenuSelections>(
                                    value: VerticalListPopupMenuSelections.onCopy,
                                    child: Text(S.of(context).dialogCopyLabel)),
                              if (totalKcal > 0)
                                PopupMenuItem<VerticalListPopupMenuSelections>(
                                    value: VerticalListPopupMenuSelections.onDelete,
                                    child: Text(S.of(context).deleteAllLabel)),
                              if (totalKcal > 0)
                                PopupMenuItem<VerticalListPopupMenuSelections>(
                                    value: VerticalListPopupMenuSelections.onShare,
                                    child: Text(S.of(context).shareMealLabel)),
                            ])),
                ],
              ),
              if (!compact && showsMacroLine)
                Padding(
                  padding: const EdgeInsets.only(top: Dimens.spacing4),
                  child: Text(
                    _buildMacroLine(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (compact)
          ..._buildIntakeCards(palette)
        else
          DragTarget<IntakeEntity>(
            onAcceptWithDetails: (intake) {
              _onItemDropped(intake.data);
            },
            builder: (context, candidateData, rejectedData) {
              return Column(
                children: [
                  ..._buildIntakeCards(palette),
                  PlaceholderCard(
                    day: widget.day,
                    onTap: () => _onPlaceholderCardTapped(context),
                    firstListElement: true,
                    semanticIdentifier: 'add-meal-placeholder',
                  ),
                ],
              );
            },
          ),
      ],
    );
    if (!compact) return section;
    return DragTarget<IntakeEntity>(
      onAcceptWithDetails: (intake) => _onItemDropped(intake.data),
      builder: (context, candidateData, rejectedData) => _MealGroupCard(
        // An entry over its own meal would not move anywhere, so only the
        // other meals light up.
        isDropTarget: candidateData.any(
          (dragged) => !widget.intakeList.any((e) => e.id == dragged?.id),
        ),
        child: section,
      ),
    );
  }

  Widget _buildTitle(
    TextTheme textTheme,
    AppPalette palette,
    FontWeight weight,
  ) {
    return AutoSizeText(
      widget.title,
      maxLines: 1,
      minFontSize: 14,
      overflow: TextOverflow.ellipsis,
      style: textTheme.titleLarge?.copyWith(
        color: palette.textStrong,
        fontWeight: weight,
      ),
    );
  }

  /// The kcal line under a meal card's title, with what was eaten standing
  /// out from the target so the meal's total outweighs its entries'.
  Widget _buildGroupSummary(
    BuildContext context,
    TextTheme textTheme,
    AppPalette palette,
  ) {
    final summary = _buildHeaderSummary(context);
    final consumed = EnergyDisplay.formatValue(context, totalKcal);
    final strong = TextStyle(
      color: palette.textStrong,
      fontWeight: FontWeight.w800,
    );
    // A translation may not open with the number; it then reads as one tone.
    final leads = summary.startsWith(consumed);
    return Text.rich(
      TextSpan(
        children: [
          if (leads) TextSpan(text: consumed, style: strong),
          TextSpan(
            text: leads ? summary.substring(consumed.length) : summary,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.labelMedium?.copyWith(
        color: palette.textMuted,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  List<Widget> _buildIntakeCards(AppPalette palette) {
    final compact = widget.compact;
    return [
      for (final (index, intakeEntity) in widget.intakeList.indexed) ...[
        // In a meal card the line under the header spans it; the lines
        // between entries are inset.
        if (compact)
          Divider(
            height: Dimens.hairline,
            thickness: Dimens.hairline,
            indent: index == 0 ? 0 : Dimens.spacing16,
            color: palette.border,
          ),
        LongPressDraggable<IntakeEntity>(
          key: ValueKey(intakeEntity.id),
          data: intakeEntity,
          onDragStarted: () => widget.onItemDragCallback?.call(true),
          onDragEnd: (_) => widget.onItemDragCallback?.call(false),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Opacity(
                opacity: 0.85,
                child: IntakeCard(
                  key: ValueKey('fb-${intakeEntity.id}'),
                  intake: intakeEntity,
                  firstListElement: false,
                  usesImperialUnits: widget.usesImperialUnits,
                  sortType: widget.sortType,
                ),
              ),
            ),
          ),
          childWhenDragging: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? Dimens.spacing8 : Dimens.spacing16,
              vertical: Dimens.spacing4,
            ),
            child: Container(
              height: compact ? IntakeCard.rowMinHeight - 8 : 76,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: compact
                    ? Dimens.borderRadiusS
                    : Dimens.borderRadiusM,
                border: compact
                    ? null
                    : Border.all(
                        color: palette.border,
                        width: Dimens.hairline,
                      ),
              ),
            ),
          ),
          child: IntakeCard(
            key: ValueKey(intakeEntity.id),
            intake: intakeEntity,
            onItemLongPressed: widget.onItemLongPressedCallback,
            onItemTapped: widget.onItemTappedCallback,
            firstListElement: false,
            grouped: compact,
            usesImperialUnits: widget.usesImperialUnits,
            sortType: widget.sortType,
          ),
        ),
      ],
    ];
  }

  Widget _buildSortMenu(BuildContext context) {
    final current = widget.sortType ?? DiarySortType.timeAdded;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Semantics(
      identifier: 'diary-section-sort-menu',
      child: PopupMenuButton<DiarySortType>(
        tooltip: S.of(context).diarySortByLabel,
        icon: Icon(Icons.sort_rounded, color: palette.textMuted),
        shape: Dimens.shapeM,
        initialValue: current,
        onSelected: (sort) => widget.onSortTypeChanged?.call(sort),
        itemBuilder: (context) => <PopupMenuEntry<DiarySortType>>[
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.timeAdded,
            checked: current == DiarySortType.timeAdded,
            child: Text(S.of(context).diarySortByTime),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.kcal,
            checked: current == DiarySortType.kcal,
            child: Text(S.of(context).diarySortByKcal),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.protein,
            checked: current == DiarySortType.protein,
            child: Text(S.of(context).diarySortByProtein),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.carbs,
            checked: current == DiarySortType.carbs,
            child: Text(S.of(context).diarySortByCarbs),
          ),
          CheckedPopupMenuItem<DiarySortType>(
            value: DiarySortType.fat,
            checked: current == DiarySortType.fat,
            child: Text(S.of(context).diarySortByFat),
          ),
        ],
      ),
    );
  }

  void _onPlaceholderCardTapped(BuildContext context) {
    Navigator.pushNamed(context, NavigationOptions.addMealRoute,
        arguments: AddMealScreenArguments(widget.addMealType, widget.day));
  }

  Future<void> _onItemDropped(IntakeEntity entity) async {
    // One move under one tracked-day lock (#1317): taken apart, a profile
    // switch queued during the add could run before the delete, which
    // would then debit the incoming profile and leave the outgoing one
    // with the entry in both meals. The refreshes below wait for both,
    // so Home does not reload with the entry in both meals either.
    await withTrackedDayLockOnProfile(() async {
      await _mealDetailBloc.addIntake(context, entity.unit,
          entity.amount.toString(), widget.addMealType.getIntakeType(),
          entity.meal, entity.dateTime);
      await _homeBloc.deleteIntakeItem(entity);
    });

    // Refresh Home Page
    locator<HomeBloc>().add(const LoadItemsEvent());

    // Refresh Diary Page
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  }
}

/// The one surface a meal lives on in Home: its header and its entries. While
/// an entry from another meal is held over it, a dashed outline marks it as
/// the place the entry will land.
class _MealGroupCard extends StatelessWidget {
  final bool isDropTarget;
  final Widget child;

  const _MealGroupCard({required this.isDropTarget, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: 6,
      ),
      child: CustomPaint(
        foregroundPainter: isDropTarget
            ? _DashedOutlinePainter(Theme.of(context).colorScheme.primary)
            : null,
        child: AppCard(bordered: false, child: child),
      ),
    );
  }
}

class _DashedOutlinePainter extends CustomPainter {
  static const double _width = 2;
  static const double _dash = 7;
  static const double _gap = 5;

  final Color color;

  const _DashedOutlinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(_width / 2),
          const Radius.circular(Dimens.radiusL - _width / 2),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter old) => old.color != color;
}
