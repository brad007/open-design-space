import 'dart:math' as math;
import 'dart:ui';

import 'package:path_parsing/path_parsing.dart';
import 'package:xml/xml.dart';

import '../model/geometry.dart';
import 'shapes.dart';

class ImportedShape {
  ImportedShape(this.contours, this.color, this.name);

  /// Millimetres, in document coordinates.
  final List<Contour> contours;
  final int color;
  final String name;
}

/// 2×3 affine matrix [a c e; b d f].
class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = Affine(1, 0, 0, 1, 0, 0);
  final double a, b, c, d, e, f;

  Affine operator *(Affine o) => Affine(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  Offset apply(Offset p) => Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);
}

Affine parseTransform(String? s) {
  if (s == null || s.trim().isEmpty) return Affine.identity;
  var m = Affine.identity;
  final re = RegExp(r'(\w+)\s*\(([^)]*)\)');
  for (final match in re.allMatches(s)) {
    final v = _numbers(match.group(2)!);
    double at(int i, [double dflt = 0]) => i < v.length ? v[i] : dflt;
    final Affine t = switch (match.group(1)) {
      'matrix' when v.length == 6 => Affine(v[0], v[1], v[2], v[3], v[4], v[5]),
      'translate' => Affine(1, 0, 0, 1, at(0), at(1)),
      'scale' => Affine(at(0, 1), 0, 0, at(1, at(0, 1)), 0, 0),
      'rotate' => () {
          final r = at(0) * math.pi / 180;
          final rot = Affine(math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0);
          final cx = at(1), cy = at(2);
          return Affine(1, 0, 0, 1, cx, cy) * rot * Affine(1, 0, 0, 1, -cx, -cy);
        }(),
      'skewX' => Affine(1, 0, math.tan(at(0) * math.pi / 180), 1, 0, 0),
      'skewY' => Affine(1, math.tan(at(0) * math.pi / 180), 0, 1, 0, 0),
      _ => Affine.identity,
    };
    m = m * t;
  }
  return m;
}

List<double> _numbers(String s) => RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
    .allMatches(s)
    .map((m) => double.parse(m.group(0)!))
    .toList();

/// Length in millimetres. Unitless values are CSS pixels (96 per inch).
double? parseLength(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^\s*([-+]?[\d.eE+-]+)\s*(mm|cm|in|pt|pc|px)?\s*$').firstMatch(s);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!);
  if (v == null) return null;
  return switch (m.group(2)) {
    'mm' => v,
    'cm' => v * 10,
    'in' => v * 25.4,
    'pt' => v * 25.4 / 72,
    'pc' => v * 25.4 / 6,
    _ => v * 25.4 / 96,
  };
}

class _ContourBuilder extends PathProxy {
  _ContourBuilder(this.m);
  final Affine m;
  final contours = <Contour>[];
  Contour? _cur;

  @override
  void moveTo(double x, double y) {
    _finish();
    _cur = Contour([PathNode(m.apply(Offset(x, y)))], closed: false);
  }

  @override
  void lineTo(double x, double y) {
    _cur ??= Contour([PathNode(m.apply(Offset(x, y)))], closed: false);
    _cur!.nodes.add(PathNode(m.apply(Offset(x, y))));
  }

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    final c = _cur;
    if (c == null) return;
    c.nodes.last.cOut = m.apply(Offset(x1, y1));
    c.nodes.add(PathNode(m.apply(Offset(x3, y3)), cIn: m.apply(Offset(x2, y2))));
  }

  @override
  void close() {
    final c = _cur;
    if (c == null) return;
    c.closed = true;
    // Merge the closing duplicate node into the first one.
    if (c.nodes.length > 1 && (c.nodes.last.p - c.nodes.first.p).distance < 1e-6) {
      final last = c.nodes.removeLast();
      c.nodes.first.cIn = last.cIn;
    }
    _finish();
  }

  void _finish() {
    final c = _cur;
    if (c != null && c.nodes.length > 1) contours.add(c);
    _cur = null;
  }
}

int? parseColor(String? s) {
  if (s == null) return null;
  s = s.trim().toLowerCase();
  if (s == 'none' || s == 'transparent') return 0;
  const named = {
    'black': 0xFF000000, 'white': 0xFFFFFFFF, 'red': 0xFFFF0000, 'green': 0xFF008000,
    'blue': 0xFF0000FF, 'yellow': 0xFFFFFF00, 'orange': 0xFFFFA500, 'purple': 0xFF800080,
    'pink': 0xFFFFC0CB, 'gray': 0xFF808080, 'grey': 0xFF808080,
  };
  if (named.containsKey(s)) return named[s];
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    final v = int.tryParse(hex, radix: 16);
    if (v != null && hex.length == 6) return 0xFF000000 | v;
  }
  final rgb = RegExp(r'rgb\(\s*(\d+)\D+(\d+)\D+(\d+)').firstMatch(s);
  if (rgb != null) {
    return 0xFF000000 |
        (int.parse(rgb.group(1)!) << 16) |
        (int.parse(rgb.group(2)!) << 8) |
        int.parse(rgb.group(3)!);
  }
  return null;
}

String? _style(XmlElement e, String prop) {
  final style = e.getAttribute('style');
  if (style != null) {
    for (final decl in style.split(';')) {
      final kv = decl.split(':');
      if (kv.length == 2 && kv[0].trim() == prop) return kv[1].trim();
    }
  }
  return e.getAttribute(prop);
}

List<ImportedShape> importSvg(String source) {
  final doc = XmlDocument.parse(source);
  final root = doc.rootElement;
  // Map the viewBox onto the document's physical size.
  var base = Affine.identity;
  final vb = root.getAttribute('viewBox');
  final w = parseLength(root.getAttribute('width'));
  final h = parseLength(root.getAttribute('height'));
  if (vb != null) {
    final v = _numbers(vb);
    if (v.length == 4 && v[2] > 0 && v[3] > 0) {
      final sx = (w ?? v[2] * 25.4 / 96) / v[2];
      final sy = (h ?? v[3] * 25.4 / 96) / v[3];
      final s = math.min(sx, sy);
      base = Affine(s, 0, 0, s, -v[0] * s, -v[1] * s);
    }
  } else {
    const px = 25.4 / 96;
    base = const Affine(px, 0, 0, px, 0, 0);
  }

  final out = <ImportedShape>[];
  var count = 0;
  void walk(XmlElement e, Affine m, int? inheritedFill) {
    final tag = e.name.local;
    if (const {'defs', 'clipPath', 'mask', 'symbol', 'style', 'title', 'metadata'}.contains(tag)) {
      return;
    }
    final mm = m * parseTransform(e.getAttribute('transform'));
    final fill = parseColor(_style(e, 'fill')) ?? inheritedFill;
    final stroke = parseColor(_style(e, 'stroke'));
    List<Contour>? contours;
    double attr(String n) => double.tryParse(e.getAttribute(n) ?? '') ?? 0;
    switch (tag) {
      case 'path':
        final d = e.getAttribute('d');
        if (d != null) {
          final b = _ContourBuilder(mm);
          writeSvgPathDataToPath(d, b);
          b._finish();
          contours = b.contours;
        }
      case 'rect':
        contours = [
          rectContour(Rect.fromLTWH(attr('x'), attr('y'), attr('width'), attr('height')))
              .transformed(mm.apply),
        ];
      case 'circle':
        final r = attr('r');
        contours = [
          ellipseContour(Rect.fromCircle(center: Offset(attr('cx'), attr('cy')), radius: r))
              .transformed(mm.apply),
        ];
      case 'ellipse':
        contours = [
          ellipseContour(Rect.fromCenter(
                  center: Offset(attr('cx'), attr('cy')),
                  width: attr('rx') * 2,
                  height: attr('ry') * 2))
              .transformed(mm.apply),
        ];
      case 'line':
        contours = [
          Contour.polyline([Offset(attr('x1'), attr('y1')), Offset(attr('x2'), attr('y2'))],
                  closed: false)
              .transformed(mm.apply),
        ];
      case 'polygon' || 'polyline':
        final v = _numbers(e.getAttribute('points') ?? '');
        contours = [
          Contour.polyline([
            for (var i = 0; i + 1 < v.length; i += 2) Offset(v[i], v[i + 1]),
          ], closed: tag == 'polygon')
              .transformed(mm.apply),
        ];
      default:
        for (final child in e.childElements) {
          walk(child, mm, fill);
        }
        return;
    }
    if (contours == null || contours.isEmpty) return;
    var color = fill ?? 0xFF000000;
    if (color == 0) color = stroke ?? 0xFF000000;
    if (color == 0) color = 0xFF000000;
    count++;
    out.add(ImportedShape(contours, color, e.getAttribute('id') ?? '$tag $count'));
  }

  walk(root, base, null);
  return out;
}
