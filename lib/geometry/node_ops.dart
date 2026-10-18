import 'dart:ui';

import '../model/geometry.dart';

/// Location on a contour: segment index plus curve parameter.
class ContourHit {
  ContourHit(this.contour, this.segment, this.t, this.point, this.distance);
  final int contour, segment;
  final double t;
  final Offset point;
  final double distance;
}

ContourHit? nearestOnContours(List<Contour> contours, Offset q) {
  ContourHit? best;
  for (var ci = 0; ci < contours.length; ci++) {
    final c = contours[ci];
    for (var si = 0; si < c.segmentCount; si++) {
      final (p0, p1, p2, p3) = c.segment(si);
      const n = 48;
      for (var k = 0; k <= n; k++) {
        final t = k / n;
        final pt = c.segmentIsLine(si) ? Offset.lerp(p0, p3, t)! : cubicPoint(p0, p1, p2, p3, t);
        final d = (pt - q).distance;
        if (best == null || d < best.distance) best = ContourHit(ci, si, t, pt, d);
      }
    }
  }
  return best;
}

/// Inserts a node on [segment] at [t], keeping the curve shape.
void insertNode(Contour c, int segment, double t) {
  final i = segment;
  final j = (i + 1) % c.nodes.length;
  if (c.segmentIsLine(i)) {
    final p = Offset.lerp(c.nodes[i].p, c.nodes[j].p, t)!;
    c.nodes.insert(i + 1, PathNode(p));
    return;
  }
  final (p0, p1, p2, p3) = c.segment(i);
  final (l, r) = splitCubic(p0, p1, p2, p3, t);
  c.nodes[i].cOut = l.$2;
  c.nodes[j].cIn = r.$3;
  c.nodes.insert(i + 1, PathNode(l.$4, cIn: l.$3, cOut: r.$2));
}

/// Removes a node. Returns false when the contour would become degenerate.
bool deleteNode(Contour c, int index) {
  final minNodes = c.closed ? 3 : 2;
  if (c.nodes.length <= minNodes) return false;
  c.nodes.removeAt(index);
  return true;
}

void moveNode(PathNode n, Offset to) {
  final d = to - n.p;
  n.p = to;
  if (n.cIn != null) n.cIn = n.cIn! + d;
  if (n.cOut != null) n.cOut = n.cOut! + d;
}

/// Turns a corner into a smooth node with symmetric handles, or back.
void toggleSmooth(Contour c, int index) {
  final n = c.nodes[index];
  if (!n.isCorner) {
    n.cIn = null;
    n.cOut = null;
    return;
  }
  final prev = c.nodes[(index - 1 + c.nodes.length) % c.nodes.length].p;
  final next = c.nodes[(index + 1) % c.nodes.length].p;
  final dir = next - prev;
  final len = dir.distance;
  if (len == 0) return;
  final unit = dir / len;
  final reach = len / 6;
  n.cIn = n.p - unit * reach;
  n.cOut = n.p + unit * reach;
}
