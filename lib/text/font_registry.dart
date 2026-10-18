import 'package:flutter/foundation.dart';

import '../platform/platform.dart';
import 'ttf.dart';

class FontRef {
  const FontRef(this.path, this.face, this.family, this.style);
  final String path;
  final int face;
  final String family, style;
}

List<FontRef> _scanFiles(List<String> paths) {
  final out = <FontRef>[];
  for (final path in paths) {
    final bytes = readBytesSync(path);
    if (bytes == null || bytes.length < 12) continue;
    final faces = fontFaceCount(bytes);
    for (var i = 0; i < faces; i++) {
      final names = TrueTypeFont.probe(bytes, i);
      if (names != null) out.add(FontRef(path, i, names.$1, names.$2));
    }
  }
  return out;
}

/// Fonts installed on this computer plus fonts the user imported.
class FontRegistry extends ChangeNotifier {
  final Map<String, Map<String, FontRef>> _families = {};
  final Map<String, TrueTypeFont> _loaded = {};
  bool ready = false;
  String? importDir;

  List<String> get families => _families.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  List<String> stylesOf(String family) {
    final s = _families[family]?.keys.toList() ?? [];
    s.sort((a, b) => _styleRank(a).compareTo(_styleRank(b)));
    return s;
  }

  static int _styleRank(String s) {
    final l = s.toLowerCase();
    if (l == 'regular' || l == 'normal' || l == 'book' || l == 'roman') return 0;
    if (l == 'bold') return 1;
    if (l.contains('italic') && !l.contains('bold')) return 2;
    return 3;
  }

  String? get defaultFamily {
    const preferred = ['Helvetica', 'Arial', 'Avenir Next', 'Segoe UI', 'DejaVu Sans', 'Liberation Sans'];
    for (final p in preferred) {
      if (_families.containsKey(p)) return p;
    }
    return families.isEmpty ? null : families.first;
  }

  Future<void> init() async {
    final dirs = [...systemFontDirs()];
    if (hasFileSystem) {
      importDir = '${await appDataDir()}/fonts';
      dirs.add(importDir!);
    }
    final files = await listFontFiles(dirs);
    final refs = await compute(_scanFiles, files);
    for (final r in refs) {
      _add(r);
    }
    ready = true;
    debugPrint('Fonts: ${_families.length} families from ${files.length} files');
    notifyListeners();
  }

  void _add(FontRef r) {
    final styles = _families.putIfAbsent(r.family, () => {});
    styles.putIfAbsent(r.style, () => r);
  }

  /// Registers fonts from a file the user picked. Returns the family names added.
  Future<List<String>> importFontFile(String path, String fileName) async {
    var usePath = path;
    if (importDir != null) {
      final store = FileStore(importDir!);
      await store.copyIn(path, fileName);
      usePath = store.absolute(fileName);
    }
    final refs = _scanFiles([usePath]);
    for (final r in refs) {
      _add(r);
    }
    notifyListeners();
    return refs.map((r) => r.family).toSet().toList();
  }

  /// Registers a font from memory (used by tests and web).
  void addLoaded(TrueTypeFont font, {String path = 'memory'}) {
    final r = FontRef('$path#${font.family}#${font.subfamily}', 0, font.family, font.subfamily);
    _add(r);
    _loaded['${r.path}:0'] = font;
    notifyListeners();
  }

  TrueTypeFont? resolve(String family, String style) {
    final styles = _families[family];
    if (styles == null || styles.isEmpty) return null;
    final ref = styles[style] ?? styles[stylesOf(family).first]!;
    final key = '${ref.path}:${ref.face}';
    final cached = _loaded[key];
    if (cached != null) return cached;
    final bytes = readBytesSync(ref.path);
    if (bytes == null) return null;
    try {
      return _loaded[key] = TrueTypeFont(bytes, faceIndex: ref.face);
    } catch (_) {
      return null;
    }
  }
}
