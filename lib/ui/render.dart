import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/geometry.dart';
import '../model/objects.dart';
import '../model/project.dart';
import 'image_cache.dart';

/// Strokes a path with dashes of [dash] and gaps of [gap] (canvas units).
void drawDashed(Canvas canvas, Path path, Paint paint, double dash, double gap) =>
    canvas.drawPath(dashedPath(path, dash, gap), paint);

final _dashCache = Expando<(double, double, Path)>();

/// [path] cut into dashes, as one path. Cached per source path, so dashing a
/// cached object outline costs nothing on later frames.
Path dashedPath(Path path, double dash, double gap) {
  final hit = _dashCache[path];
  if (hit != null && hit.$1 == dash && hit.$2 == gap) return hit.$3;
  final out = Path();
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  _dashCache[path] = (dash, gap, out);
  return out;
}

final _pathCache = Expando<(int, Path)>();

/// [o]'s outline as a Path in local units, rebuilt only when its geometry
/// changes. Building paths every frame was the main cost with big designs.
Path objectPath(DesignObject o) {
  final key = o.geometryKey;
  final hit = _pathCache[o];
  if (hit != null && hit.$1 == key) return hit.$2;
  final path = contoursToPath(o.localContours);
  _pathCache[o] = (key, path);
  return path;
}

/// Draws one object in canvas units of millimetres. [pxPerMm] keeps hairlines
/// a constant on-screen width.
void paintObject(Canvas canvas, DesignObject o, AssetImages? images, double pxPerMm, {double opacity = 1}) {
  final hair = 1.2 / pxPerMm;
  final color = Color(o.color).withValues(alpha: opacity);
  canvas.save();
  canvas.transform(o.xform.toMatrix4());
  final local = o.localContours;
  final path = objectPath(o);
  final closed = local.isNotEmpty && local.every((c) => c.closed);
  final scale = (o.xform.sx.abs() + o.xform.sy.abs()) / 2;
  final strokeW = (0.5 / scale).clamp(hair, double.infinity);

  if (o is ImageObject) {
    final img = images?[o.assetId];
    canvas.save();
    canvas.clipRect(o.visibleRect);
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        o.fullRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(alpha: opacity),
      );
    } else {
      canvas.drawRect(o.fullRect, Paint()..color = Colors.grey.withValues(alpha: 0.3 * opacity));
    }
    canvas.restore();
    if (o.cutOutline != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hair * 1.5 / scale
          ..color = const Color(0xFFE5484D).withValues(alpha: opacity),
      );
    }
    canvas.restore();
    return;
  }

  switch (o.operation) {
    case Operation.cut || Operation.print || Operation.kissCut:
      if (closed) {
        canvas.drawPath(path, Paint()..color = o.operation == Operation.kissCut ? color.withValues(alpha: 0.75 * opacity) : color);
        if (o.operation == Operation.kissCut) {
          drawDashed(canvas, path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = hair / scale
            ..color = Colors.black54, 3 / pxPerMm / scale, 2 / pxPerMm / scale);
        }
      } else {
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..color = color);
      }
    case Operation.draw:
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color);
    case Operation.score:
      drawDashed(canvas, path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(strokeW, 2 * hair / scale)
        ..color = color, 3 / scale, 1.5 / scale);
    case Operation.guide:
      drawDashed(canvas, path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hair / scale
        ..color = Colors.grey.withValues(alpha: opacity), 2 / scale, 2 / scale);
  }
  canvas.restore();
}

/// Renders [objects] fitted into a [size]-pixel image.
Future<ui.Image> renderToImage(List<DesignObject> objects, AssetImages? images, Size size, {Color? background, Rect? frame}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  if (background != null) canvas.drawColor(background, BlendMode.src);
  final visible = objects.where((o) => o.visible).toList();
  if (visible.isNotEmpty) {
    final b = frame ?? visible.map((o) => o.worldBounds()).reduce((a, c) => a.expandToInclude(c));
    final pad = math.max(b.width, b.height) * 0.06 + 0.5;
    final r = b.inflate(pad);
    final s = math.min(size.width / r.width, size.height / r.height);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-r.center.dx, -r.center.dy);
    for (final o in visible) {
      paintObject(canvas, o, images, s);
    }
  }
  return rec.endRecording().toImage(size.width.round(), size.height.round());
}

Future<Uint8List?> renderPng(List<DesignObject> objects, AssetImages? images, Size size, {Color? background}) async {
  final img = await renderToImage(objects, images, size, background: background);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data?.buffer.asUint8List();
}

/// A PNG of the design at [dpi], for printing or sharing.
Future<Uint8List?> exportDesignPng(Project p, AssetImages images, {double dpi = 300}) async {
  final visible = p.objects.where((o) => o.visible).toList();
  if (visible.isEmpty) return null;
  final b = visible.map((o) => o.worldBounds()).reduce((a, c) => a.expandToInclude(c));
  final pxPerMm = dpi / 25.4;
  final w = (b.width * pxPerMm).clamp(1, 12000).toDouble();
  final h = (b.height * pxPerMm).clamp(1, 12000).toDouble();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = math.min(w / b.width, h / b.height);
  canvas.scale(s);
  canvas.translate(-b.left, -b.top);
  for (final o in visible) {
    paintObject(canvas, o, images, s);
  }
  final img = await rec.endRecording().toImage(w.round(), h.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data?.buffer.asUint8List();
}
