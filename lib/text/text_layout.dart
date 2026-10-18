import 'dart:math' as math;
import 'dart:ui';

import '../model/geometry.dart';
import '../model/objects.dart';
import 'font_registry.dart';
import 'ttf.dart';

/// Lays out [t] with [font] into contours in millimetres, centered on the origin.
List<Contour> layoutText(TextObject t, TrueTypeFont font) {
  final scale = t.size / font.unitsPerEm;
  final spacing = t.letterSpacing * font.unitsPerEm;
  final lineAdvance = font.lineHeight * t.lineSpacing;

  // Glyph placements per line, in font units relative to the line start.
  final lines = <List<(int glyph, double x, double advance)>>[];
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

/// Keeps text outlines in step with their settings.
class TextEngine {
  TextEngine(this.fonts);
  final FontRegistry fonts;

  /// Returns true when the outline changed.
  bool refresh(TextObject t) {
    if (t.outlineKey == t.layoutKey && !t.fontMissing && t.outline.isNotEmpty) return false;
    final font = fonts.resolve(t.fontFamily, t.fontStyle);
    if (font == null) {
      // Keep the outline saved in the file so the design still shows and cuts.
      t.fontMissing = true;
      return false;
    }
    t.outline = layoutText(t, font);
    t.outlineKey = t.layoutKey;
    t.fontMissing = false;
    return true;
  }
}
