import 'dart:typed_data';
import 'dart:ui';

import '../model/geometry.dart';

enum TraceMode {
  /// Pixels darker than the threshold become the shape.
  dark,

  /// Opaque pixels become the shape (good for PNGs with transparency).
  opaque,
}

/// Traces a binary mask of an RGBA image into closed outlines, in pixel units.
///
/// Every inside pixel contributes the sides that face an outside pixel; the
/// directed sides are then chained into loops, so the result always closes and
/// holes come out as separate loops for even-odd filling.
List<List<Offset>> traceImage(
  Uint8List rgba,
  int width,
  int height, {
  TraceMode mode = TraceMode.dark,
  double threshold = 0.5,
  double simplify = 0.8,
  int minPixels = 6,
}) {
  final inside = Uint8List(width * height);
  final t = (threshold * 255).round();
  for (var i = 0; i < width * height; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2], a = rgba[i * 4 + 3];
    final on = switch (mode) {
      TraceMode.opaque => a > t,
      // Treat transparent as background.
      TraceMode.dark => a > 32 && (0.299 * r + 0.587 * g + 0.114 * b) < t,
    };
    inside[i] = on ? 1 : 0;
  }
  bool at(int x, int y) => x >= 0 && y >= 0 && x < width && y < height && inside[y * width + x] == 1;

  // Directed boundary edges keyed by start vertex.
  final stride = width + 1;
  final next = <int, List<int>>{};
  void edge(int x0, int y0, int x1, int y1) =>
      (next[y0 * stride + x0] ??= []).add(y1 * stride + x1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!at(x, y)) continue;
      if (!at(x, y - 1)) edge(x, y, x + 1, y);
      if (!at(x + 1, y)) edge(x + 1, y, x + 1, y + 1);
      if (!at(x, y + 1)) edge(x + 1, y + 1, x, y + 1);
      if (!at(x - 1, y)) edge(x, y + 1, x, y);
    }
  }

  final loops = <List<Offset>>[];
  while (next.isNotEmpty) {
    final start = next.keys.first;
    final loop = <Offset>[];
    var v = start;
    while (true) {
      loop.add(Offset((v % stride).toDouble(), (v ~/ stride).toDouble()));
      final outs = next[v];
      if (outs == null || outs.isEmpty) break;
      final w = outs.removeLast();
      if (outs.isEmpty) next.remove(v);
      v = w;
      if (v == start) break;
    }
    if (loop.length >= 4 && polygonArea(loop).abs() >= minPixels) {
      final closedRun = [...loop, loop.first];
      final s = simplifyPolyline(closedRun, simplify)..removeLast();
      if (s.length >= 3) loops.add(s);
    }
  }
  return loops;
}
