import 'dart:math' as math;
import 'dart:ui';

import '../model/geometry.dart';
import '../model/objects.dart';
import '../model/project.dart';

/// Room left around the print sheet edge for registration marks, mm.
const registrationInset = 10.0;

/// A piece placed on a mat: a single object or a group sharing a color.
class MatItem {
  MatItem({required this.key, required this.objects, required this.polylines, required this.size, required this.origin});

  final String key;

  /// Top-left of the item on the canvas, mm.
  final Offset origin;
  final List<DesignObject> objects;

  /// Outlines relative to the item's top-left, mm.
  final List<(DesignObject, List<List<Offset>>)> polylines;
  final Size size;

  /// Top-left on the mat, mm.
  Offset offset = Offset.zero;
  bool manual = false;

  Rect get rect => offset & size;

  /// Maps a canvas point into mat coordinates.
  Offset toMat(Offset canvas) => canvas - origin + offset;
}

class Mat {
  Mat({required this.key, required this.baseKey, required this.label, required this.color, required this.isPrint, required this.size});

  final String key, baseKey, label;
  final int color;
  final bool isPrint;
  final Size size;
  final items = <MatItem>[];
  final warnings = <String>[];

  /// Cut as a mirror image (heat-transfer vinyl is cut face down).
  bool mirror = false;

  /// Where a mat point is cut, after mirroring.
  Offset cutPoint(Offset p) => mirror ? Offset(size.width - p.dx, p.dy) : p;

  /// Area items may occupy, mm.
  Rect usable(MatSettings s) => isPrint
      ? Rect.fromLTWH(0, 0, size.width, size.height).deflate(s.printMargin + registrationInset)
      : Rect.fromLTWH(0, 0, size.width, size.height).deflate(s.margin);
}

String colorHex(int c) => (c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// A friendly name for a mat color, e.g. "Blue".
String colorName(int c) {
  const names = {
    'Black': 0x111827, 'Gray': 0x6B7280, 'Silver': 0xB8B8B8, 'White': 0xFFFFFF, 'Red': 0xE5484D,
    'Orange': 0xF76B15, 'Gold': 0xF5A524, 'Yellow': 0xFFE629, 'Green': 0x30A46C, 'Teal': 0x12A594,
    'Sky': 0x0090FF, 'Blue': 0x2F6FED, 'Purple': 0x8E4EC6, 'Pink': 0xD6409F, 'Brown': 0x8B5A2B,
    'Mint': 0x7CE2B4, 'Blush': 0xFFC0CB, 'Navy': 0x1E2A78,
  };
  int ch(int v, int shift) => (v >> shift) & 0xFF;
  var best = '';
  var bestD = double.infinity;
  for (final e in names.entries) {
    final dr = ch(c, 16) - ch(e.value, 16), dg = ch(c, 8) - ch(e.value, 8), db = ch(c, 0) - ch(e.value, 0);
    // Weighted RGB distance, close enough for labels.
    final d = 2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db;
    if (d < bestD) {
      bestD = d;
      best = e.key;
    }
  }
  return best;
}

String baseMatKey(DesignObject o) => o.operation == Operation.print ? 'print' : 'c:${colorHex(o.color)}';

List<Mat> planMats(Project p) {
  final s = p.mat;
  // Collect items: objects sharing a group and mat land together.
  final byItem = <String, List<DesignObject>>{};
  final itemBase = <String, String>{};
  for (final o in p.objects) {
    if (!o.visible || !o.operation.isMachined) continue;
    final base = baseMatKey(o);
    final key = o.groupId == null ? o.id : '${o.groupId}@$base';
    (byItem[key] ??= []).add(o);
    itemBase[key] = base;
  }

  final itemsByBase = <String, List<MatItem>>{};
  final canvasPos = <String, Offset>{};
  for (final e in byItem.entries) {
    final lines = [for (final o in e.value) (o, o.worldPolylines(0.05))];
    final all = lines.expand((l) => l.$2.expand((pts) => pts));
    final b = boundsOfPoints(all);
    final rel = [
      for (final (o, pl) in lines) (o, [for (final pts in pl) [for (final q in pts) q - b.topLeft]]),
    ];
    final item = MatItem(key: e.key, objects: e.value, polylines: rel, size: b.size, origin: b.topLeft);
    canvasPos[e.key] = b.topLeft;
    (itemsByBase[itemBase[e.key]!] ??= []).add(item);
  }

  final mats = <Mat>[];
  for (final entry in itemsByBase.entries) {
    final base = entry.key;
    final isPrint = base == 'print';
    final size = isPrint ? Size(s.printSheet.width, s.printSheet.height) : Size(s.matSize.width, s.matSize.height);
    final color = isPrint ? 0xFF000000 : entry.value.first.objects.first.color;
    final label = isPrint ? 'Print then Cut' : '${colorName(color)} #${colorHex(color)}';
    final group = <Mat>[];
    Mat newMat() {
      final m = Mat(
        key: '$base#${group.length + 1}',
        baseKey: base,
        label: '$label · ${group.length + 1}',
        color: color,
        isPrint: isPrint,
        size: size,
      );
      group.add(m);
      return m;
    }

    final items = entry.value;
    final pending = <MatItem>[];
    // Hand-placed items first.
    for (final it in items) {
      final pl = s.placements[it.key];
      if (pl != null && pl.matKey.startsWith('$base#')) {
        final idx = int.tryParse(pl.matKey.split('#').last) ?? 1;
        while (group.length < idx) {
          newMat();
        }
        it
          ..offset = pl.offset
          ..manual = true;
        group[idx - 1].items.add(it);
      } else {
        pending.add(it);
      }
    }
    if (group.isEmpty) newMat();
    final usable = group.first.usable(s);

    if (!s.autoPack && pending.isNotEmpty) {
      // Keep the canvas arrangement if it fits on one mat.
      final union = boundsOfPoints(pending.expand((it) => [canvasPos[it.key]!, canvasPos[it.key]! + it.size.bottomRight(Offset.zero)]));
      if (union.width <= usable.width && union.height <= usable.height && group.first.items.isEmpty) {
        for (final it in pending) {
          it.offset = usable.topLeft + (canvasPos[it.key]! - union.topLeft);
          group.first.items.add(it);
        }
        pending.clear();
      } else {
        group.first.warnings.add("The canvas arrangement doesn't fit on one mat, so items were packed.");
      }
    }

    // Shelf packing, tallest first.
    pending.sort((a, b) => b.size.height.compareTo(a.size.height));
    var matIndex = 0;
    var cursor = usable.topLeft;
    var shelfH = 0.0;
    for (final it in pending) {
      if (it.size.width > usable.width || it.size.height > usable.height) {
        final m = newMat();
        it.offset = usable.topLeft;
        m.items.add(it);
        m.warnings.add('"${it.objects.first.name}" is larger than the mat.');
        continue;
      }
      while (true) {
        final m = group[matIndex];
        if (cursor.dx + it.size.width > usable.right + 1e-6) {
          cursor = Offset(usable.left, cursor.dy + shelfH + s.spacing);
          shelfH = 0;
        }
        final fits = cursor.dy + it.size.height <= usable.bottom + 1e-6;
        final candidate = cursor & it.size;
        final overlaps = m.items.any((o) => o.manual && o.rect.inflate(s.spacing / 2).overlaps(candidate));
        if (fits && !overlaps) {
          it.offset = cursor;
          m.items.add(it);
          cursor = cursor.translate(it.size.width + s.spacing, 0);
          shelfH = math.max(shelfH, it.size.height);
          break;
        }
        if (fits && overlaps) {
          cursor = cursor.translate(math.max(s.spacing, 2), 0);
          continue;
        }
        matIndex++;
        if (matIndex >= group.length) newMat();
        cursor = usable.topLeft;
        shelfH = 0;
      }
    }
    for (final m in group) {
      m.mirror = !isPrint && s.mirrored.contains(m.key);
    }
    mats.addAll(group.where((m) => m.items.isNotEmpty));
  }

  // Apply the user's order, then default ordering for the rest.
  int rank(Mat m) {
    final i = s.order.indexOf(m.key);
    return i < 0 ? 1 << 20 : i;
  }

  mats.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    if (a.isPrint != b.isPrint) return a.isPrint ? -1 : 1;
    return a.key.compareTo(b.key);
  });
  return mats;
}
