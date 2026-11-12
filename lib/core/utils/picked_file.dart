import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Whether [picked] is something [readPickedBytes] can read.
///
/// A file picked on a phone or desktop has a path. In a browser it never
/// does: the page only gets a handle to the file, so a missing path there is
/// normal, not a failed pick.
bool isReadablePick(PlatformFile? picked) =>
    picked != null && (kIsWeb || picked.path != null);

/// Reads the bytes of a file chosen with the file picker.
///
/// On the web `File(path)` does not exist, so the bytes come from the picker's
/// own handle. Elsewhere this is the plain `File(path).readAsBytes()` the
/// import code always used.
///
/// Check [isReadablePick] first: a native pick without a path throws here.
Future<Uint8List> readPickedBytes(PlatformFile picked) async {
  if (kIsWeb) return picked.readAsBytes();
  final path = picked.path;
  if (path == null) {
    throw StateError('The picked file "${picked.name}" has no path');
  }
  return File(path).readAsBytes();
}
