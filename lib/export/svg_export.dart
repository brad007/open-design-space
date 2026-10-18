import 'dart:convert';
import 'dart:ui';

import '../mat/mat_planner.dart';
import '../model/geometry.dart';
import '../model/objects.dart';
import '../model/project.dart';

String _n(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

String _hex(int c) => '#${colorHex(c)}';

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

/// SVG path data for contours after mapping each point through [map].
String contoursToPathData(List<Contour> contours, Offset Function(Offset) map) {
  final b = StringBuffer();
  for (final c in contours) {
    if (c.nodes.isEmpty) continue;
    final s = map(c.nodes.first.p);
    b.write('M${_n(s.dx)} ${_n(s.dy)}');
    for (var i = 0; i < c.segmentCount; i++) {
      final (_, p1, p2, p3) = c.segment(i);
      if (c.segmentIsLine(i)) {
        final q = map(p3);
        b.write('L${_n(q.dx)} ${_n(q.dy)}');
      } else {
        final a = map(p1), bb = map(p2), q = map(p3);
        b.write('C${_n(a.dx)} ${_n(a.dy)} ${_n(bb.dx)} ${_n(bb.dy)} ${_n(q.dx)} ${_n(q.dy)}');
      }
    }
    if (c.closed) b.write('Z');
  }
  return b.toString();
}

String polylinesToPathData(List<List<Offset>> polys, {bool closed = true}) {
  final b = StringBuffer();
  for (final p in polys) {
    if (p.isEmpty) continue;
    b.write('M${_n(p.first.dx)} ${_n(p.first.dy)}');
    for (final q in p.skip(1)) {
      b.write('L${_n(q.dx)} ${_n(q.dy)}');
    }
    if (closed) b.write('Z');
  }
  return b.toString();
}

Rect designBounds(Project p) {
  final rects = [for (final o in p.objects) if (o.visible) o.worldBounds()];
  if (rects.isEmpty) return Rect.zero;
  return rects.reduce((a, b) => a.expandToInclude(b));
}

/// The whole design as a layered SVG in millimetres. Curves are kept, images
/// are embedded, and each element records its operation for other tools.
String exportDesignSvg(Project p, {double padding = 2}) {
  final r = designBounds(p).inflate(padding);
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="${_n(r.width)}mm" height="${_n(r.height)}mm" viewBox="${_n(r.left)} ${_n(r.top)} ${_n(r.width)} ${_n(r.height)}">')
    ..writeln('<!-- Made with Open Design Space -->');
  for (final o in p.objects) {
    if (!o.visible) continue;
    final attrs = 'id="${_esc(o.id)}" data-name="${_esc(o.name)}" data-operation="${o.operation.name}"';
    if (o is ImageObject) {
      final asset = p.assets[o.assetId];
      if (asset == null) continue;
      final m = o.xform.toMatrix4();
      final full = o.fullRect;
      final clipId = 'clip-${o.id}';
      final vis = o.visibleRect;
      b
        ..writeln('<clipPath id="$clipId"><rect x="${_n(vis.left)}" y="${_n(vis.top)}" width="${_n(vis.width)}" height="${_n(vis.height)}"/></clipPath>')
        ..writeln('<g $attrs transform="matrix(${_n(m[0])} ${_n(m[1])} ${_n(m[4])} ${_n(m[5])} ${_n(m[12])} ${_n(m[13])})">'
            '<image clip-path="url(#$clipId)" x="${_n(full.left)}" y="${_n(full.top)}" width="${_n(full.width)}" height="${_n(full.height)}" '
            'preserveAspectRatio="none" xlink:href="data:${asset.mime};base64,${base64Encode(asset.bytes)}"/></g>');
      continue;
    }
    final d = contoursToPathData(o.localContours, o.xform.apply);
    final style = switch (o.operation) {
      Operation.score => 'fill="none" stroke="${_hex(o.color)}" stroke-width="0.5" stroke-dasharray="2 1"',
      Operation.draw => 'fill="none" stroke="${_hex(o.color)}" stroke-width="0.5"',
      Operation.guide => 'fill="none" stroke="#999999" stroke-width="0.3"',
      _ => o.localContours.every((c) => c.closed)
          ? 'fill="${_hex(o.color)}" fill-rule="evenodd"'
          : 'fill="none" stroke="${_hex(o.color)}" stroke-width="0.5"',
    };
    b.writeln('<path $attrs $style d="$d"/>');
  }
  b.writeln('</svg>');
  return b.toString();
}

/// One mat as stroke-only paths, positioned as they'll be cut.
String exportMatSvg(Mat mat, MatSettings s, {bool includeRegistration = true}) {
  final w = mat.size.width, h = mat.size.height;
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${_n(w)}mm" height="${_n(h)}mm" viewBox="0 0 ${_n(w)} ${_n(h)}">')
    ..writeln('<!-- ${_esc(mat.label)} · Open Design Space -->');
  for (final it in mat.items) {
    for (final (o, polys) in it.polylines) {
      final moved = [for (final p in polys) [for (final q in p) mat.cutPoint(q + it.offset)]];
      final closed = o.localContours.every((c) => c.closed);
      final dash = o.operation == Operation.score ? ' stroke-dasharray="2 1"' : '';
      b.writeln('<path data-operation="${o.operation.name}" fill="none" stroke="${_hex(o.color)}" stroke-width="0.25"$dash '
          'd="${polylinesToPathData(moved, closed: closed)}"/>');
    }
  }
  if (mat.isPrint && includeRegistration) {
    b.writeln('<g data-operation="registration" fill="none" stroke="#000000" stroke-width="0.5">'
        '<path d="${polylinesToPathData(registrationMarks(mat, s), closed: false)}"/></g>');
  }
  b.writeln('</svg>');
  return b.toString();
}

/// Corner marks for Print then Cut: a solid square top-left plus L marks at
/// the other corners, inside the registration band.
List<List<Offset>> registrationMarks(Mat mat, MatSettings s) {
  final r = Rect.fromLTWH(0, 0, mat.size.width, mat.size.height).deflate(s.printMargin);
  const len = 8.0;
  return [
    [r.topLeft, r.topLeft.translate(5, 0), r.topLeft.translate(5, 5), r.topLeft.translate(0, 5), r.topLeft],
    [r.topRight.translate(-len, 0), r.topRight, r.topRight.translate(0, len)],
    [r.bottomLeft.translate(0, -len), r.bottomLeft, r.bottomLeft.translate(len, 0)],
    [r.bottomRight.translate(-len, 0), r.bottomRight, r.bottomRight.translate(0, -len)],
  ];
}
