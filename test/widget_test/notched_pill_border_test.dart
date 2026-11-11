import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/notched_pill_border.dart';

void main() {
  const border = NotchedPillBorder(notchRadius: 34);
  const rect = Rect.fromLTWH(0, 0, 360, 72);
  final path = border.getOuterPath(rect);

  test('the bite is cut under the middle of the top edge', () {
    expect(path.contains(const Offset(180, 2)), isFalse);
    expect(path.contains(const Offset(180, 30)), isFalse);
    // Below the bite's lowest point the bar is whole again.
    expect(path.contains(const Offset(180, 38)), isTrue);
    expect(path.contains(const Offset(180, 70)), isTrue);
  });

  test('the rest of the pill is solid', () {
    expect(path.contains(const Offset(36, 36)), isTrue);
    expect(path.contains(const Offset(324, 36)), isTrue);
    expect(path.contains(const Offset(100, 4)), isTrue);
    expect(path.contains(const Offset(260, 4)), isTrue);
  });

  test('the ends are round', () {
    // The corners of the bounding box are outside a pill.
    expect(path.contains(const Offset(2, 2)), isFalse);
    expect(path.contains(const Offset(358, 70)), isFalse);
    expect(path.contains(const Offset(2, 36)), isTrue);
  });

  test('the bite joins the top edge with rounded corners', () {
    // The join is a fillet, not a sharp V: just outside the bite the edge dips
    // away from the top line, and it is back on the line past the fillet.
    expect(path.contains(const Offset(180 + 37, 0.5)), isFalse);
    expect(path.contains(const Offset(180 + 46, 0.5)), isTrue);
  });

  testWidgets('draws as a material shape without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          shape: border,
          color: Colors.grey,
          clipBehavior: Clip.antiAlias,
          child: const SizedBox(width: 360, height: 72),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
