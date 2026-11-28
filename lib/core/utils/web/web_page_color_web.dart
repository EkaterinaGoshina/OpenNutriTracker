import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('ontSetPageColor')
external void _setPageColor(JSString color);

/// Paints the page behind the Flutter view, which iOS uses to tint the status
/// bar area of the home-screen app.
void setWebPageColor(Color color) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  try {
    _setPageColor('#$rgb'.toJS);
  } catch (_) {
    // A cached index.html from before this function existed.
  }
}
