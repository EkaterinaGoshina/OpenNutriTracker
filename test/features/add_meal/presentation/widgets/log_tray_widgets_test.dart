import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/log_tray_widgets.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

MealEntity _meal(String name, double kcal100) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal100,
    carbohydrates100: 10,
    fat100: 5,
    proteins100: 3,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

/// [kcal] of a 100 kcal/100 g food, as one row: the grams are the kcal.
LogTrayItem _item(String name, double kcal) => LogTrayItem(
  meal: _meal(name, 100),
  unit: 'g',
  amount: kcal,
  amountLabel: '$kcal g',
);

Future<void> _pumpTray(
  WidgetTester tester,
  LogTray tray, {
  bool kilojoules = false,
  bool startCollapsed = false,
}) => tester.pumpWidget(
  ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: kilojoules),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [
            LogTrayList(tray: tray, startCollapsed: startCollapsed),
            LogTrayLogButton(tray: tray, onPressed: () {}),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  group('the To-log rows add up to the total under them (#1469)', () {
    testWidgets('the 2.6.0 case: 80.85 + 14.7 reads 81 + 15 = 96', (
      tester,
    ) async {
      final tray = LogTray()
        ..add(_item('Nutella', 80.85))
        ..add(_item('Apple', 14.7));
      await _pumpTray(tester, tray);

      expect(find.text('80.85 g · 81 kcal'), findsOneWidget);
      expect(find.text('14.7 g · 15 kcal'), findsOneWidget);
      expect(find.text('96 kcal'), findsOneWidget);
    });

    testWidgets('the total is the sum of the rows as shown', (tester) async {
      // 94.8 kcal exactly, but the rows read 80 and 14.
      final tray = LogTray()
        ..add(_item('A', 80.4))
        ..add(_item('B', 14.4));
      await _pumpTray(tester, tray);

      expect(find.text('80.4 g · 80 kcal'), findsOneWidget);
      expect(find.text('14.4 g · 14 kcal'), findsOneWidget);
      expect(find.text('94 kcal'), findsOneWidget);
    });

    testWidgets('in kJ too', (tester) async {
      final tray = LogTray()
        ..add(_item('A', 80.4))
        ..add(_item('B', 14.4));
      await _pumpTray(tester, tray, kilojoules: true);

      expect(find.text('80.4 g · 336 kJ'), findsOneWidget);
      expect(find.text('14.4 g · 60 kJ'), findsOneWidget);
      expect(find.text('396 kJ'), findsOneWidget);
    });
  });

  group('a collapsed list keeps the screen above the results short', () {
    testWidgets('shows only the title line until it is tapped', (tester) async {
      final tray = LogTray()
        ..add(_item('Rice', 80))
        ..add(_item('Bread', 15));
      await _pumpTray(tester, tray, startCollapsed: true);

      expect(find.text('TO LOG · 2'), findsOneWidget);
      expect(find.text('80.0 g · 80 kcal'), findsNothing);
      expect(find.text('15.0 g · 15 kcal'), findsNothing);
      // The total under it still says what is on the list.
      expect(find.text('95 kcal'), findsOneWidget);

      await tester.tap(find.text('TO LOG · 2'));
      await tester.pump();
      expect(find.text('80.0 g · 80 kcal'), findsOneWidget);
      expect(find.text('15.0 g · 15 kcal'), findsOneWidget);

      await tester.tap(find.text('TO LOG · 2'));
      await tester.pump();
      expect(find.text('80.0 g · 80 kcal'), findsNothing);
    });

    testWidgets('is a fraction of the height of the open list', (tester) async {
      final tray = LogTray()
        ..add(_item('Rice', 80))
        ..add(_item('Bread', 15))
        ..add(_item('Egg', 70));
      await _pumpTray(tester, tray);
      final open = tester.getSize(find.byType(LogTrayList)).height;

      // A fresh tree, so the open list's state is not carried over.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpTray(tester, tray, startCollapsed: true);
      final folded = tester.getSize(find.byType(LogTrayList)).height;

      expect(folded, lessThan(open / 2));
    });

    testWidgets('open by default, as before', (tester) async {
      final tray = LogTray()..add(_item('Rice', 80));
      await _pumpTray(tester, tray);
      expect(find.text('80.0 g · 80 kcal'), findsOneWidget);
    });

    testWidgets('Clear works while it is folded', (tester) async {
      final tray = LogTray()..add(_item('Rice', 80));
      await _pumpTray(tester, tray, startCollapsed: true);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(tray.isEmpty, isTrue);
    });
  });
}
