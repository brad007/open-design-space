import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const bool hasFileSystem = true;

/// Folders where the operating system keeps installed fonts.
List<String> systemFontDirs() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (Platform.isMacOS) {
    return [
      '/System/Library/Fonts',
      '/System/Library/Fonts/Supplemental',
      '/Library/Fonts',
      '$home/Library/Fonts',
    ];
  }
  if (Platform.isWindows) {
    final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    return ['$win\\Fonts', '$local\\Microsoft\\Windows\\Fonts'];
  }
  if (Platform.isLinux) {
    return ['/usr/share/fonts', '/usr/local/share/fonts', '$home/.fonts', '$home/.local/share/fonts'];
  }
  return const [];
}

/// Font files under [dirs], searched recursively.
Future<List<String>> listFontFiles(List<String> dirs) async {
  final out = <String>[];
  for (final d in dirs) {
    final dir = Directory(d);
    if (!await dir.exists()) continue;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final p = e.path.toLowerCase();
          if (p.endsWith('.ttf') || p.endsWith('.ttc') || p.endsWith('.otf')) out.add(e.path);
        }
      }
    } on FileSystemException {
      // Unreadable folders are skipped.
    }
  }
  return out;
}

Uint8List? readBytesSync(String path) {
  try {
    return File(path).readAsBytesSync();
  } on FileSystemException {
    return null;
  }
}

String? _dataDirOverride;

/// Lets tests point storage at a temporary folder.
void setDataDirForTesting(String path) => _dataDirOverride = path;

Future<String> appDataDir() async {
  final base = _dataDirOverride ?? (await getApplicationSupportDirectory()).path;
  await Directory(base).create(recursive: true);
  return base;
}

class FileStore {
  FileStore(this.root);
  final String root;

  String _p(String rel) => '$root/$rel';

  Future<void> ensureDir(String rel) => Directory(_p(rel)).create(recursive: true);

  Future<List<String>> list(String rel) async {
    final d = Directory(_p(rel));
    if (!await d.exists()) return [];
    return [
      await for (final e in d.list())
        if (e is File) e.uri.pathSegments.last,
    ];
  }

  Future<String?> readString(String rel) async {
    final f = File(_p(rel));
    return await f.exists() ? f.readAsString() : null;
  }

  Future<Uint8List?> readBytes(String rel) async {
    final f = File(_p(rel));
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Writes to a temp file then renames, so a crash mid-write never leaves a
  /// half-written project behind.
  Future<void> writeAtomic(String rel, List<int> bytes) async {
    final target = File(_p(rel));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  Future<void> delete(String rel) async {
    final f = File(_p(rel));
    if (await f.exists()) await f.delete();
  }

  Future<void> deleteDir(String rel) async {
    final d = Directory(_p(rel));
    if (await d.exists()) await d.delete(recursive: true);
  }


  String absolute(String rel) => _p(rel);
}
