import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_dialog.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

IntakeEntity _intake({double? fat100 = 10}) => IntakeEntity(
  id: 'entry',
  unit: 'g',
  amount: 100,
  type: IntakeTypeEntity.breakfast,
  dateTime: DateTime(2026, 1, 1),
  meal: MealEntity(
    code: 'meal',
    name: 'Cottage cheese',
    url: null,
    mealQuantity: '100',
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: '100 g',
    nutriments: MealNutrimentsEntity(
      energyKcal100: 200,
      carbohydrates100: 20,
      fat100: fat100,
      proteins100: 5,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
);

Future<void> _pump(WidgetTester tester, IntakeEntity intake) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<EnergyUnitProvider>(
      create: (_) => EnergyUnitProvider(),
      child: MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: EditDialog(intakeEntity: intake, usesImperialUnits: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the nutrition of the portion and follows the amount', (
    tester,
  ) async {
    await _pump(tester, _intake());

    expect(find.text('Cottage cheese'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('5 g'), findsOneWidget);
    expect(find.text('10 g'), findsOneWidget);
    expect(find.text('20 g'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '150');
    await tester.pump();

    expect(find.text('300'), findsOneWidget);
    expect(find.text('7.5 g'), findsOneWidget);
    expect(find.text('15 g'), findsOneWidget);
    expect(find.text('30 g'), findsOneWidget);
  });

  testWidgets('a missing figure is a dash, not zero', (tester) async {
    await _pump(tester, _intake(fat100: null));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0 g'), findsNothing);
  });

  testWidgets('an empty field shows dashes for every value', (tester) async {
    await _pump(tester, _intake());

    await tester.enterText(find.byType(TextFormField), '');
    await tester.pump();

    expect(find.text('—'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
