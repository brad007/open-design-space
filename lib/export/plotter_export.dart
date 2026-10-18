import 'dart:ui';

import '../mat/mat_planner.dart';
import '../model/objects.dart';

/// Polylines on a mat with the operation that produced them.
Iterable<(Operation, int, List<Offset>, bool)> matPaths(Mat mat) sync* {
  for (final it in mat.items) {
    for (final (o, polys) in it.polylines) {
      final closed = o.localContours.every((c) => c.closed);
      for (final p in polys) {
        yield (o.operation, o.color, [for (final q in p) mat.cutPoint(q + it.offset)], closed);
      }
    }
  }
}

/// DXF (R12-compatible) with one polyline per contour, in millimetres.
/// Layers are named by operation so CAM tools can treat them differently.
String exportMatDxf(Mat mat) {
  final b = StringBuffer();
  void g(int code, Object v) => b
    ..writeln(code)
    ..writeln(v);
  g(0, 'SECTION');
  g(2, 'HEADER');
  g(9, r'$INSUNITS');
  g(70, 4);
  g(0, 'ENDSEC');
  g(0, 'SECTION');
  g(2, 'ENTITIES');
  for (final (op, _, pts, closed) in matPaths(mat)) {
    g(0, 'POLYLINE');
    g(8, op.name.toUpperCase());
    g(66, 1);
    g(70, closed ? 1 : 0);
    for (final p in pts) {
      g(0, 'VERTEX');
      g(8, op.name.toUpperCase());
      g(10, p.dx.toStringAsFixed(4));
      // DXF is y-up.
      g(20, (mat.size.height - p.dy).toStringAsFixed(4));
    }
    g(0, 'SEQEND');
  }
  g(0, 'ENDSEC');
  g(0, 'EOF');
  return b.toString();
}

/// HPGL for generic plotters and vinyl cutters: 40 plotter units per mm,
/// origin bottom-left. Cut/kiss-cut use pen 1; score/draw use pen 2.
String exportMatHpgl(Mat mat) {
  final b = StringBuffer('IN;');
  int u(double mm) => (mm * 40).round();
  var pen = 0;
  for (final (op, _, pts, closed) in matPaths(mat)) {
    if (pts.isEmpty) continue;
    final want = (op == Operation.score || op == Operation.draw) ? 2 : 1;
    if (want != pen) {
      b.write('SP$want;');
      pen = want;
    }
    final run = closed ? [...pts, pts.first] : pts;
    String xy(Offset p) => '${u(p.dx)},${u(mat.size.height - p.dy)}';
    b.write('PU${xy(run.first)};PD');
    b.write(run.skip(1).map(xy).join(','));
    b.write(';');
  }
  b.write('PU0,0;SP0;');
  return b.toString();
}
