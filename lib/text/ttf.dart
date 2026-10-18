import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../model/geometry.dart';

class UnsupportedFontException implements Exception {
  UnsupportedFontException(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedFontException: $message';
}

/// Number of faces in a .ttf/.otf (1) or .ttc collection.
int fontFaceCount(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  if (bytes.length >= 12 && d.getUint32(0) == 0x74746366) return d.getUint32(8);
  return 1;
}

/// A minimal TrueType (glyf) reader: metrics, cmap, kerning and outlines.
/// CFF-flavored OpenType fonts are rejected.
class TrueTypeFont {
  TrueTypeFont(Uint8List bytes, {int faceIndex = 0}) : _b = ByteData.sublistView(bytes) {
    var offset = 0;
    if (_b.getUint32(0) == 0x74746366) {
      final n = _b.getUint32(8);
      if (faceIndex >= n) throw RangeError.index(faceIndex, n);
      offset = _b.getUint32(12 + faceIndex * 4);
    }
    final numTables = _b.getUint16(offset + 4);
    for (var i = 0; i < numTables; i++) {
      final rec = offset + 12 + i * 16;
      final tag = String.fromCharCodes(Uint8List.sublistView(_b, rec, rec + 4));
      _tables[tag] = (_b.getUint32(rec + 8), _b.getUint32(rec + 12));
    }
    if (!_tables.containsKey('glyf') || !_tables.containsKey('loca')) {
      throw UnsupportedFontException('Only TrueType-outline fonts are supported');
    }
    final head = _t('head');
    unitsPerEm = _b.getUint16(head + 18);
    _longLoca = _b.getInt16(head + 50) == 1;
    numGlyphs = _b.getUint16(_t('maxp') + 4);
    final hhea = _t('hhea');
    ascender = _b.getInt16(hhea + 4);
    descender = _b.getInt16(hhea + 6);
    lineGap = _b.getInt16(hhea + 8);
    _numHMetrics = _b.getUint16(hhea + 34);
    _readNames();
  }

  /// Reads only the names, for fast font discovery. Returns null when the
  /// face can't be used.
  static (String family, String style)? probe(Uint8List bytes, int faceIndex) {
    try {
      final f = TrueTypeFont(bytes, faceIndex: faceIndex);
      if (f.family.isEmpty) return null;
      return (f.family, f.subfamily);
    } catch (_) {
      return null;
    }
  }

  final ByteData _b;
  final _tables = <String, (int, int)>{};
  late final int unitsPerEm, numGlyphs, ascender, descender, lineGap;
  late final bool _longLoca;
  late final int _numHMetrics;
  String family = '';
  String subfamily = 'Regular';
  late final Map<int, int> _cmap = _readCmap();
  late final Map<int, int> _kern = _readKern();
  final _glyphCache = <int, List<Contour>>{};

  int _t(String tag) {
    final t = _tables[tag];
    if (t == null) throw UnsupportedFontException('Missing $tag table');
    return t.$1;
  }

  double get lineHeight => (ascender - descender + lineGap).toDouble();

  int glyphIndex(int codePoint) => _cmap[codePoint] ?? 0;

  int advanceWidth(int glyph) {
    final hmtx = _t('hmtx');
    final i = glyph < _numHMetrics ? glyph : _numHMetrics - 1;
    return _b.getUint16(hmtx + i * 4);
  }

  int kerning(int left, int right) => _kern[(left << 16) | right] ?? 0;

  void _readNames() {
    final t = _tables['name'];
    if (t == null) return;
    final base = t.$1;
    final count = _b.getUint16(base + 2);
    final strings = base + _b.getUint16(base + 4);
    final found = <int, String>{};
    for (var i = 0; i < count; i++) {
      final r = base + 6 + i * 12;
      final platform = _b.getUint16(r), encoding = _b.getUint16(r + 2);
      final language = _b.getUint16(r + 4);
      final nameId = _b.getUint16(r + 6);
      final len = _b.getUint16(r + 8), off = _b.getUint16(r + 10);
      if (!const {1, 2, 16, 17}.contains(nameId)) continue;
      final raw = Uint8List.sublistView(_b, strings + off, strings + off + len);
      String? s;
      if (platform == 3 && (encoding == 1 || encoding == 10) && (language == 0x409 || !found.containsKey(nameId))) {
        final units = [for (var k = 0; k + 1 < raw.length; k += 2) (raw[k] << 8) | raw[k + 1]];
        s = String.fromCharCodes(units);
      } else if (platform == 1 && encoding == 0 && !found.containsKey(nameId)) {
        s = latin1.decode(raw);
      }
      if (s != null && s.isNotEmpty) found[nameId] = s;
    }
    family = found[16] ?? found[1] ?? '';
    subfamily = found[17] ?? found[2] ?? 'Regular';
  }

  Map<int, int> _readCmap() {
    final cmap = <int, int>{};
    final base = _t('cmap');
    final n = _b.getUint16(base + 2);
    int? best;
    var bestScore = -1;
    for (var i = 0; i < n; i++) {
      final r = base + 4 + i * 8;
      final platform = _b.getUint16(r), encoding = _b.getUint16(r + 2);
      final sub = base + _b.getUint32(r + 4);
      final format = _b.getUint16(sub);
      final score = switch ((platform, encoding, format)) {
        (3, 10, 12) || (0, 4, 12) || (0, 6, 12) => 4,
        (3, 1, 4) || (0, 3, 4) => 3,
        (0, _, 4) => 2,
        (_, _, 4) || (_, _, 12) => 1,
        _ => -1,
      };
      if (score > bestScore) {
        bestScore = score;
        best = sub;
      }
    }
    if (best == null) return cmap;
    final format = _b.getUint16(best);
    if (format == 4) {
      final segX2 = _b.getUint16(best + 6);
      final ends = best + 14;
      final starts = ends + segX2 + 2;
      final deltas = starts + segX2;
      final ranges = deltas + segX2;
      for (var s = 0; s < segX2 ~/ 2; s++) {
        final end = _b.getUint16(ends + s * 2);
        final start = _b.getUint16(starts + s * 2);
        final delta = _b.getInt16(deltas + s * 2);
        final rangeOffAddr = ranges + s * 2;
        final rangeOff = _b.getUint16(rangeOffAddr);
        for (var c = start; c <= end && c != 0xFFFF; c++) {
          int g;
          if (rangeOff == 0) {
            g = (c + delta) & 0xFFFF;
          } else {
            final addr = rangeOffAddr + rangeOff + (c - start) * 2;
            if (addr + 1 >= _b.lengthInBytes) continue;
            g = _b.getUint16(addr);
            if (g != 0) g = (g + delta) & 0xFFFF;
          }
          if (g != 0) cmap[c] = g;
        }
      }
    } else if (format == 12) {
      final groups = _b.getUint32(best + 12);
      for (var i = 0; i < groups; i++) {
        final r = best + 16 + i * 12;
        final start = _b.getUint32(r), end = _b.getUint32(r + 4), g0 = _b.getUint32(r + 8);
        for (var c = start; c <= end && c - start < 0x10000; c++) {
          cmap[c] = g0 + (c - start);
        }
      }
    }
    return cmap;
  }

  Map<int, int> _readKern() {
    final kern = <int, int>{};
    final t = _tables['kern'];
    if (t == null) return kern;
    final base = t.$1;
    if (_b.getUint16(base) != 0) return kern; // Only the Windows-style table.
    final nTables = _b.getUint16(base + 2);
    var sub = base + 4;
    for (var i = 0; i < nTables; i++) {
      final length = _b.getUint16(sub + 2);
      final coverage = _b.getUint16(sub + 4);
      if ((coverage >> 8) == 0 && (coverage & 1) == 1) {
        final nPairs = _b.getUint16(sub + 6);
        for (var p = 0; p < nPairs; p++) {
          final r = sub + 14 + p * 6;
          kern[(_b.getUint16(r) << 16) | _b.getUint16(r + 2)] = _b.getInt16(r + 4);
        }
      }
      sub += length;
    }
    return kern;
  }

  (int, int) _glyphRange(int g) {
    final loca = _t('loca');
    if (_longLoca) {
      return (_b.getUint32(loca + g * 4), _b.getUint32(loca + g * 4 + 4));
    }
    return (_b.getUint16(loca + g * 2) * 2, _b.getUint16(loca + g * 2 + 2) * 2);
  }

  /// Outline in font units, y up.
  List<Contour> glyphOutline(int g, [int depth = 0]) {
    if (g < 0 || g >= numGlyphs || depth > 8) return const [];
    final cached = _glyphCache[g];
    if (cached != null) return cached;
    final (start, end) = _glyphRange(g);
    if (end <= start) return _glyphCache[g] = const [];
    final o = _t('glyf') + start;
    final nContours = _b.getInt16(o);
    final result = nContours >= 0 ? _simpleGlyph(o, nContours) : _compositeGlyph(o, depth);
    return _glyphCache[g] = result;
  }

  List<Contour> _simpleGlyph(int o, int nContours) {
    var p = o + 10;
    final ends = [for (var i = 0; i < nContours; i++) _b.getUint16(p + i * 2)];
    p += nContours * 2;
    final nPts = ends.isEmpty ? 0 : ends.last + 1;
    p += 2 + _b.getUint16(p);
    final flags = Uint8List(nPts);
    for (var i = 0; i < nPts;) {
      final f = _b.getUint8(p++);
      flags[i++] = f;
      if (f & 8 != 0) {
        var rep = _b.getUint8(p++);
        while (rep-- > 0 && i < nPts) {
          flags[i++] = f;
        }
      }
    }
    final xs = List<int>.filled(nPts, 0), ys = List<int>.filled(nPts, 0);
    var v = 0;
    for (var i = 0; i < nPts; i++) {
      final f = flags[i];
      if (f & 2 != 0) {
        final d = _b.getUint8(p++);
        v += (f & 16 != 0) ? d : -d;
      } else if (f & 16 == 0) {
        v += _b.getInt16(p);
        p += 2;
      }
      xs[i] = v;
    }
    v = 0;
    for (var i = 0; i < nPts; i++) {
      final f = flags[i];
      if (f & 4 != 0) {
        final d = _b.getUint8(p++);
        v += (f & 32 != 0) ? d : -d;
      } else if (f & 32 == 0) {
        v += _b.getInt16(p);
        p += 2;
      }
      ys[i] = v;
    }
    final contours = <Contour>[];
    var s = 0;
    for (final e in ends) {
      final pts = [
        for (var i = s; i <= e; i++) (Offset(xs[i].toDouble(), ys[i].toDouble()), flags[i] & 1 != 0),
      ];
      s = e + 1;
      final c = quadContour(pts);
      if (c != null) contours.add(c);
    }
    return contours;
  }

  List<Contour> _compositeGlyph(int o, int depth) {
    var p = o + 10;
    final out = <Contour>[];
    while (true) {
      final flags = _b.getUint16(p);
      final glyph = _b.getUint16(p + 2);
      p += 4;
      double dx, dy;
      if (flags & 1 != 0) {
        dx = _b.getInt16(p).toDouble();
        dy = _b.getInt16(p + 2).toDouble();
        p += 4;
      } else {
        dx = _b.getInt8(p).toDouble();
        dy = _b.getInt8(p + 1).toDouble();
        p += 2;
      }
      if (flags & 2 == 0) dx = dy = 0; // Point-matching offsets aren't supported.
      double f2(int at) => _b.getInt16(at) / 16384.0;
      var a = 1.0, b = 0.0, c = 0.0, d = 1.0;
      if (flags & 8 != 0) {
        a = d = f2(p);
        p += 2;
      } else if (flags & 0x40 != 0) {
        a = f2(p);
        d = f2(p + 2);
        p += 4;
      } else if (flags & 0x80 != 0) {
        a = f2(p);
        b = f2(p + 2);
        c = f2(p + 4);
        d = f2(p + 6);
        p += 8;
      }
      for (final con in glyphOutline(glyph, depth + 1)) {
        out.add(con.transformed((q) => Offset(a * q.dx + c * q.dy + dx, b * q.dx + d * q.dy + dy)));
      }
      if (flags & 0x20 == 0) break;
    }
    return out;
  }
}

/// Builds a contour from TrueType points (on-curve flag per point), turning
/// each quadratic segment into an exact cubic.
Contour? quadContour(List<(Offset, bool)> pts) {
  if (pts.length < 2) return null;
  // Expand implied on-curve midpoints between consecutive off-curve points.
  final seq = <(Offset, bool)>[];
  for (var i = 0; i < pts.length; i++) {
    final cur = pts[i], nxt = pts[(i + 1) % pts.length];
    seq.add(cur);
    if (!cur.$2 && !nxt.$2) seq.add(((cur.$1 + nxt.$1) / 2, true));
  }
  final first = seq.indexWhere((e) => e.$2);
  if (first < 0) return null;
  final ordered = [...seq.sublist(first), ...seq.sublist(0, first)];
  final nodes = <PathNode>[PathNode(ordered.first.$1)];
  for (var i = 1; i <= ordered.length; i++) {
    final cur = ordered[i % ordered.length];
    if (cur.$2) {
      if (i == ordered.length) break; // Back at the start.
      nodes.add(PathNode(cur.$1));
    } else {
      final q = cur.$1;
      final endPt = ordered[(i + 1) % ordered.length].$1;
      final from = nodes.last;
      from.cOut = from.p + (q - from.p) * (2 / 3);
      final cIn = endPt + (q - endPt) * (2 / 3);
      if (i + 1 >= ordered.length) {
        nodes.first.cIn = cIn;
        break;
      }
      nodes.add(PathNode(endPt, cIn: cIn));
      i++;
    }
  }
  return Contour(nodes);
}
