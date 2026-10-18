import 'dart:math' as math;
import 'dart:ui';

import '../model/geometry.dart';
import '../model/objects.dart';
import 'font_registry.dart';
import 'ttf.dart';

typedef _Line = List<(int glyph, double x, double advance)>;

/// Glyph placements per line, in font units relative to the line start, and
/// each line's width.
(List<_Line>, List<double>) _shapeLines(TextObject t, TrueTypeFont font) {
  final spacing = t.letterSpacing * font.unitsPerEm;
  final lines = <_Line>[];
  final widths = <double>[];
  for (final line in t.text.split('\n')) {
    final placed = <(int, double, double)>[];
    var x = 0.0;
    int? prev;
    for (final rune in line.runes) {
      final g = font.glyphIndex(rune);
      if (prev != null && t.useKerning) x += font.kerning(prev, g);
      final adv = font.advanceWidth(g).toDouble();
      placed.add((g, x, adv));
      x += adv + spacing;
      prev = g;
    }
    lines.add(placed);
    widths.add(placed.isEmpty ? 0 : x - spacing);
  }
  return (lines, widths);
}

/// Lays out [t] with [font] into contours in millimetres, centered on the origin.
List<Contour> layoutText(TextObject t, TrueTypeFont font) {
  final scale = t.size / font.unitsPerEm;
  final lineAdvance = font.lineHeight * t.lineSpacing;
  final (lines, widths) = _shapeLines(t, font);
  final maxW = widths.fold(0.0, math.max);

  final angle = t.curve.clamp(-360.0, 360.0) * math.pi / 180;
  final curved = angle.abs() > 1e-3 && maxW > 0;
  final sign = angle >= 0 ? 1.0 : -1.0;
  final radius = curved ? maxW / angle.abs() : 0.0;

  final out = <Contour>[];
  for (var li = 0; li < lines.length; li++) {
    final baseline = li * lineAdvance;
    final shift = switch (t.align) {
      TextAlign2.left => 0.0,
      TextAlign2.center => (maxW - widths[li]) / 2,
      TextAlign2.right => maxW - widths[li],
    };
    for (final (g, gx, adv) in lines[li]) {
      final outline = font.glyphOutline(g);
      if (outline.isEmpty) continue;
      if (!curved) {
        for (final c in outline) {
          out.add(c.transformed((p) => Offset((shift + gx + p.dx) * scale, (baseline - p.dy) * scale)));
        }
        continue;
      }
      // Each glyph sits rigidly on a circle; lines are concentric arcs.
      final glyphCenter = shift + gx + adv / 2 - maxW / 2;
      final r = math.max(radius - sign * baseline, font.unitsPerEm * 0.05);
      final alpha = glyphCenter / r;
      final centerY = sign * radius;
      final px = r * math.sin(alpha);
      final py = sign > 0 ? centerY - r * math.cos(alpha) : centerY + r * math.cos(alpha);
      final rot = sign * alpha;
      final c = math.cos(rot), s = math.sin(rot);
      for (final con in outline) {
        out.add(con.transformed((p) {
          final dx = p.dx - adv / 2, dy = -p.dy;
          return Offset((px + dx * c - dy * s) * scale, (py + dx * s + dy * c) * scale);
        }));
      }
    }
  }
  if (out.isEmpty) return out;
  final center = boundsOfContours(out).center;
  return [for (final c in out) c.transformed((p) => p - center)];
}

/// A flattened path in world millimetres that text can follow, measured by
/// arc length.
class TextPath {
  TextPath(List<Offset> pts, {required bool closed}) : this._(_clean(pts, closed), closed);

  TextPath._(this.points, this.closed) {
    var acc = 0.0;
    cumulative.add(0);
    for (var i = 0; i < segmentCount; i++) {
      acc += (_pt(i + 1) - _pt(i)).distance;
      cumulative.add(acc);
    }
    length = acc;
  }

  /// The longest contour of [o], oriented so text sits outside a closed shape.
  /// Null when [o] has nothing long enough to follow.
  static TextPath? of(PathObject o) {
    TextPath? best;
    for (final c in o.contours) {
      if (c.nodes.length < 2) continue;
      final scale = (o.xform.sx.abs() + o.xform.sy.abs()) / 2;
      final pts = [for (final p in c.flatten(0.02 / (scale == 0 ? 1 : scale))) o.xform.apply(p)];
      final path = TextPath(pts, closed: c.closed);
      if (best == null || path.length > best.length) best = path;
    }
    return best == null || best.length < 1e-6 ? null : best;
  }

  /// Points without repeats. A closed path runs clockwise on screen, so the
  /// left of the direction of travel (where text stands) is the outside.
  static List<Offset> _clean(List<Offset> pts, bool closed) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isEmpty || (out.last - p).distance > 1e-9) out.add(p);
    }
    if (closed && out.length > 1 && (out.first - out.last).distance < 1e-9) out.removeLast();
    if (closed && polygonArea(out) < 0) return out.reversed.toList();
    return out;
  }

  final List<Offset> points;
  final bool closed;
  final List<double> cumulative = [];
  late final double length;

  int get segmentCount => closed ? points.length : math.max(0, points.length - 1);
  Offset _pt(int i) => points[i % points.length];

  /// The same path run backwards, so the point [s] mm along this path is
  /// [length] - s along the result.
  TextPath reversed() => TextPath._(
        closed ? [points.first, ...points.skip(1).toList().reversed] : points.reversed.toList(),
        closed,
      );

  /// The point [s] mm along the path. Closed paths wrap around; open paths
  /// continue straight past their ends.
  Offset pointAt(double s) {
    if (points.length == 1 || length == 0) return points.first;
    final n = segmentCount;
    if (closed) {
      s %= length;
    } else if (s <= 0) {
      final d = _pt(1) - _pt(0);
      return _pt(0) + d / math.max(d.distance, 1e-12) * s;
    } else if (s >= length) {
      final d = _pt(n) - _pt(n - 1);
      return _pt(n) + d / math.max(d.distance, 1e-12) * (s - length);
    }
    // Binary search for the segment holding s.
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumulative[mid] <= s) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final segLen = cumulative[lo + 1] - cumulative[lo];
    final f = segLen <= 0 ? 0.0 : (s - cumulative[lo]) / segLen;
    return Offset.lerp(_pt(lo), _pt(lo + 1), f)!;
  }

  /// Fraction of the length at the vertex nearest the top of the path, where
  /// text on a closed shape usually starts out centered.
  double get topFraction {
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].dy < points[best].dy - 1e-9) best = i;
    }
    return length == 0 ? 0 : cumulative[best] / length;
  }

  /// Changes whenever the path's shape or position does.
  String get signature => '$closed|${Object.hashAll(points)}';
}

/// Where a glyph sits on a path: the baseline point under its center and the
/// direction of its baseline in radians (clockwise on screen).
typedef GlyphPlacement = ({Offset position, double angle});

/// Places glyphs centered [centers] mm along [path], with their baselines
/// [normalOffset] mm off the path on its left (outside of a closed shape).
/// Each glyph's angle follows the chord across its own [halfWidths] so it
/// rests on the path rather than on one point of a sharp turn.
List<GlyphPlacement> placeAlongPath(
  TextPath path,
  List<double> centers, {
  List<double>? halfWidths,
  double normalOffset = 0,
}) {
  return [
    for (var i = 0; i < centers.length; i++)
      () {
        final s = centers[i];
        final h = math.max(halfWidths?[i] ?? 0, 0.05);
        final d = path.pointAt(s + h) - path.pointAt(s - h);
        final angle = d.distance < 1e-12 ? 0.0 : math.atan2(d.dy, d.dx);
        // Left of travel on a y-down screen.
        final normal = Offset(math.sin(angle), -math.cos(angle));
        return (position: path.pointAt(s) + normal * normalOffset, angle: angle);
      }(),
  ];
}

/// Lays out [t] along [path] into contours in world millimetres. Each line is
/// a parallel run further from the path; [TextObject.pathStart] anchors the
/// text according to its alignment.
List<Contour> layoutTextOnPath(TextObject t, TrueTypeFont font, TextPath path) {
  final scale = t.size / font.unitsPerEm;
  final lineAdvance = font.lineHeight * t.lineSpacing * scale;
  final (lines, widths) = _shapeLines(t, font);
  final run = t.pathFlip ? path.reversed() : path;
  final anchor = (t.pathFlip ? 1 - t.pathStart : t.pathStart) * run.length;

  final out = <Contour>[];
  for (var li = 0; li < lines.length; li++) {
    final w = widths[li] * scale;
    final start = switch (t.align) {
      TextAlign2.left => anchor,
      TextAlign2.center => anchor - w / 2,
      TextAlign2.right => anchor - w,
    };
    final glyphs = [for (final g in lines[li]) if (font.glyphOutline(g.$1).isNotEmpty) g];
    final placements = placeAlongPath(
      run,
      [for (final (_, gx, adv) in glyphs) start + (gx + adv / 2) * scale],
      halfWidths: [for (final (_, _, adv) in glyphs) adv / 2 * scale],
      normalOffset: t.pathOffset - li * lineAdvance,
    );
    for (var i = 0; i < glyphs.length; i++) {
      final (g, _, adv) = glyphs[i];
      final (:position, :angle) = placements[i];
      final c = math.cos(angle), s = math.sin(angle);
      for (final con in font.glyphOutline(g)) {
        out.add(con.transformed((p) {
          final dx = (p.dx - adv / 2) * scale, dy = -p.dy * scale;
          return Offset(position.dx + dx * c - dy * s, position.dy + dx * s + dy * c);
        }));
      }
    }
  }
  return out;
}

/// Keeps text outlines in step with their settings.
class TextEngine {
  TextEngine(this.fonts);
  final FontRegistry fonts;

  /// Returns true when the outline changed. With a [path], the text follows
  /// it and its placement is reset to sit on the path.
  bool refresh(TextObject t, {TextPath? path}) {
    final key = path == null ? t.layoutKey : '${t.layoutKey}|${path.signature}';
    final anchor = t.pathAnchor;
    // A freshly loaded text has no anchor yet and is laid out again.
    if (t.outlineKey == key && !t.fontMissing && t.outline.isNotEmpty && (path == null || anchor != null)) {
      if (path == null || _onAnchor(t)) return false;
      // Moved off its path on its own: put it back.
      t.xform = Xform(tx: anchor!.dx, ty: anchor.dy);
      return true;
    }
    final font = fonts.resolve(t.fontFamily, t.fontStyle);
    if (font == null) {
      // Keep the outline saved in the file so the design still shows and cuts.
      t.fontMissing = true;
      return false;
    }
    if (path == null) {
      t.outline = layoutText(t, font);
      t.pathAnchor = null;
    } else {
      final world = layoutTextOnPath(t, font, path);
      final center = world.isEmpty ? path.pointAt(0) : boundsOfContours(world).center;
      t.outline = [for (final c in world) c.transformed((p) => p - center)];
      t.xform = Xform(tx: center.dx, ty: center.dy);
      t.pathAnchor = center;
    }
    t.outlineKey = key;
    t.fontMissing = false;
    return true;
  }

  static bool _onAnchor(TextObject t) {
    final a = t.pathAnchor, x = t.xform;
    return a != null && x.tx == a.dx && x.ty == a.dy && x.rotation == 0 && x.sx == 1 && x.sy == 1;
  }
}
