import 'dart:io';

import 'package:path_provider/path_provider.dart';

const Set<String> _videoExtensions = {'.mp4', '.mov', '.temp'};

/// Deletes exercise recordings stranded by a crash or OS kill.
///
/// Recordings are normally deleted when their screen disposes, but a
/// mid-session process death leaves an unencrypted video of the patient in
/// the cache directory. This sweep runs at startup, off the critical path.
Future<int> sweepOrphanedRecordings() async {
  var removed = 0;
  for (final dir in await _candidateDirectories()) {
    if (!await dir.exists()) continue;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot == -1 || !_videoExtensions.contains(name.substring(dot))) {
        continue;
      }
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // Locked or already gone; the next launch retries.
      }
    }
  }
  return removed;
}

Future<List<Directory>> _candidateDirectories() async {
  final dirs = <Directory>[];
  try {
    dirs.add(await getTemporaryDirectory());
  } catch (_) {}
  try {
    dirs.add(await getApplicationCacheDirectory());
  } catch (_) {}
  return dirs;
}
