import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage.dart';

/// Browser pickers return blobs rather than paths. Stage their bytes in the
/// session file system so the existing bounded decoders can read them.
Future<String?> pickedFilePath(
  PlatformFile? selected, {
  int? maximumBytes,
}) async {
  if (selected == null) return null;
  if (!kIsWeb) return selected.path;
  if (maximumBytes != null) {
    final length = await selected.length();
    if (length == null || length > maximumBytes) {
      throw FormatException('Selected file exceeds $maximumBytes bytes.');
    }
  }
  final directory = temporaryDirectory.createTempSync('import-');
  final destination = fileAt(p.join(directory.path, p.basename(selected.name)));
  final sink = destination.openWrite();
  try {
    var count = 0;
    await for (final chunk in selected.readAsByteStream()) {
      count += chunk.length;
      if (maximumBytes != null && count > maximumBytes) {
        throw FormatException('Selected file exceeds $maximumBytes bytes.');
      }
      sink.add(chunk);
    }
    await sink.flush();
  } catch (_) {
    await sink.close();
    await directory.delete(recursive: true);
    rethrow;
  }
  await sink.close();
  return destination.path;
}
