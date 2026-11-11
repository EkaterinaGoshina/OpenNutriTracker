import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('ontSafeAreaJson')
external JSString? _safeAreaJson();

/// Safe-area insets (notch, Dynamic Island, home indicator) of the page.
///
/// Flutter's web engine does not read CSS `env(safe-area-inset-*)`, so
/// `web/index.html` measures it and exposes it through `ontSafeAreaJson`.
EdgeInsets readWebSafeArea() {
  try {
    final raw = _safeAreaJson()?.toDart;
    if (raw == null) return EdgeInsets.zero;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    double v(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return EdgeInsets.fromLTRB(v('left'), v('top'), v('right'), v('bottom'));
  } catch (_) {
    return EdgeInsets.zero;
  }
}
