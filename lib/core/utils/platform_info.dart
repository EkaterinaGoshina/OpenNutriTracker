import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Web-safe stand-in for the `dart:io` [Platform] getters the app used to
/// read directly.
///
/// On the web every [Platform] getter throws [UnsupportedError], so each read
/// is guarded by [kIsWeb]. On native targets the answers are exactly what
/// [Platform] returns, which keeps host tests (macOS, Linux) behaving as
/// they did before: `defaultTargetPlatform` is not used here because
/// `flutter test` reports Android for it on every host.
abstract final class PlatformInfo {
  static bool get isWeb => kIsWeb;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// The device locale as `language_COUNTRY` (for example `de_DE`), the shape
  /// [Platform.localeName] has on iOS and Android.
  static String get localeName => kIsWeb
      ? PlatformDispatcher.instance.locale.toString()
      : Platform.localeName;
}
