import 'dart:convert';
import 'dart:typed_data';

/// Web builds keep everything in memory for the session.
const bool hasFileSystem = false;

List<String> systemFontDirs() => const [];

Future<List<String>> listFontFiles(List<String> dirs) async => const [];

final _memory = <String, Uint8List>{};

Uint8List? readBytesSync(String path) => _memory[path];

void setDataDirForTesting(String path) {}

Future<String> appDataDir() async => '/memory';

class FileStore {
  FileStore(this.root);
  final String root;

  String _p(String rel) => '$root/$rel';

  Future<void> ensureDir(String rel) async {}

  Future<List<String>> list(String rel) async {
    final prefix = '${_p(rel)}/';
    return [
      for (final k in _memory.keys)
        if (k.startsWith(prefix) && !k.substring(prefix.length).contains('/')) k.substring(prefix.length),
    ];
  }

  Future<String?> readString(String rel) async {
    final b = _memory[_p(rel)];
    return b == null ? null : utf8.decode(b);
  }

  Future<Uint8List?> readBytes(String rel) async => _memory[_p(rel)];

  Future<void> writeAtomic(String rel, List<int> bytes) async =>
      _memory[_p(rel)] = Uint8List.fromList(bytes);

  Future<void> delete(String rel) async => _memory.remove(_p(rel));

  Future<void> deleteDir(String rel) async =>
      _memory.removeWhere((k, _) => k.startsWith('${_p(rel)}/'));

  Future<void> copyIn(String sourcePath, String rel) async {}

  String absolute(String rel) => _p(rel);
}
