// Run after flutter build web. Uses only SDK libraries and runs on CI, Docker
// and developer machines. Renderer files are local so offline boot needs no CDN.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final root = Directory('build/web');
  if (!await File('${root.path}/main.dart.js').exists()) {
    stderr.writeln(
      'Build the Flutter Web release before preparing offline resources.',
    );
    exitCode = 1;
    return;
  }
  final paths = await root
      .list(recursive: true)
      .where((e) => e is File)
      .cast<File>()
      .toList();
  paths.sort((a, b) => a.path.compareTo(b.path));
  final files = <String>[];
  var hash = 0x811c9dc5;
  var bytes = 0;
  for (final file in paths) {
    final relative = file.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    if (relative.endsWith('.map') ||
        relative == 'offline-manifest.js' ||
        relative == 'flutter_service_worker.js' ||
        relative == 'build-info.json' ||
        relative.startsWith('.')) {
      continue;
    }
    final data = await file.readAsBytes();
    files.add(relative);
    bytes += data.length;
    for (final byte in [...utf8.encode(relative), ...data]) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
  }
  final manifest = {
    'version': hash.toRadixString(16),
    'files': files,
    'bytes': bytes,
  };
  await File(
    '${root.path}/offline-manifest.js',
  ).writeAsString('self.TESIIS_MANIFEST = ${jsonEncode(manifest)};\n');
  stdout.writeln(
    'Offline shell: ${files.length} files, ${(bytes / 1048576).toStringAsFixed(1)} MiB, version ${manifest['version']}',
  );
}
