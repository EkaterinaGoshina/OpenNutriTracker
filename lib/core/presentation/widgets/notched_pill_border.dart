import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A pill with a round bite out of the top edge at the centre, where the Add
/// button sits half in and half out of the bar. The rounded-pill counterpart of
/// a `BottomAppBar`'s notch, which only works on a full-width rectangle.
///
/// Where the bite meets the top edge the corners are rounded by [fillet], so
/// the join is smooth like the system's own bars instead of a sharp V.
class NotchedPillBorder extends ShapeBorder {
  final double notchRadius;
  final double fillet;

  /// Colour of the hairline drawn along the outline, instead of a shadow:
  /// an elevation shadow follows this path every frame, which is costly on a
  /// phone browser, while a stroked line is a single cheap draw.
  final Color? borderColor;

  const NotchedPillBorder({
    required this.notchRadius,
    this.fillet = 8,
    this.borderColor,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = rect.height / 2;
    final cx = rect.center.dx;
    final top = rect.top;
    // A fillet circle of radius [fillet] touches the top edge and the
    // notch circle from outside; these are where it meets each.
    final dx = math.sqrt(math.pow(notchRadius + fillet, 2) - fillet * fillet);
    final k = notchRadius / (notchRadius + fillet);
    final path = Path()
      ..moveTo(rect.left + r, top)
      ..lineTo(cx - dx, top)
      // Left fillet, top of its circle down to the notch circle.
      ..arcToPoint(
        Offset(cx - dx * k, top + fillet * k),
        radius: Radius.circular(fillet),
      )
      // The bite itself, under the button.
      ..arcToPoint(
        Offset(cx + dx * k, top + fillet * k),
        radius: Radius.circular(notchRadius),
        clockwise: false,
      )
      // Right fillet, back up to the top edge.
      ..arcToPoint(Offset(cx + dx, top), radius: Radius.circular(fillet))
      ..lineTo(rect.right - r, top)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left + r, top), radius: Radius.circular(r))
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final color = borderColor;
    if (color == null) return;
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  ShapeBorder scale(double t) => NotchedPillBorder(
    notchRadius: notchRadius * t,
    fillet: fillet * t,
    borderColor: borderColor,
  );
}
