import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_design_space/geometry/background_removal.dart';
import 'package:open_design_space/model/objects.dart';
import 'package:open_design_space/model/project.dart';

import 'editor_test.dart' show makeEditor;

const w = 20, h = 20;

/// White background, a red ring from 5 to 14 with a white hole inside, and a
/// slightly off-white speck in the top-left corner region.
Uint8List sample() {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final ring = x >= 5 && x <= 14 && y >= 5 && y <= 14;
      final hole = x >= 8 && x <= 11 && y >= 8 && y <= 11;
      final (r, g, b) = ring && !hole ? (220, 30, 30) : (255, 255, 255);
      px.setAll(i, [r, g, b, 255]);
    }
  }
  // Near-white noise on the background.
  px.setAll((1 * w + 1) * 4, [245, 247, 250, 255]);
  return px;
}

int alpha(Uint8List px, int x, int y) => px[(y * w + x) * 4 + 3];

void main() {
  test('corner colour is the background colour', () {
    expect(sampleCornerColor(sample(), w, h), 0xFFFFFFFF);
  });

  test('removes the background reached from the edges, keeps enclosed colour', () {
    final src = sample();
    final out = removeBackground(src, w, h, tolerance: 0.1);
    expect(alpha(out, 0, 0), 0);
    expect(alpha(out, 19, 19), 0);
    expect(alpha(out, 1, 1), 0, reason: 'near-white speck is within tolerance');
    expect(out.sublist(0, 4), [0, 0, 0, 0]);
    // The ring stays opaque and unchanged.
    expect(alpha(out, 5, 5), 255);
    expect(out.sublist((5 * w + 5) * 4, (5 * w + 5) * 4 + 3), [220, 30, 30]);
    // White inside the ring isn't connected to the edge.
    expect(alpha(out, 9, 9), 255);
    // The source is left untouched.
    expect(alpha(src, 0, 0), 255);
  });

  test('zero tolerance keeps the off-white speck', () {
    final out = removeBackground(sample(), w, h, tolerance: 0);
    expect(alpha(out, 0, 0), 0);
    expect(alpha(out, 1, 1), 255);
  });

  test('a picked colour removes that colour instead', () {
    // Red background with a white square: picking red clears the outside.
    final px = Uint8List(w * h * 4);
    for (var p = 0; p < w * h; p++) {
      final x = p % w, y = p ~/ w;
      final inside = x >= 6 && x <= 13 && y >= 6 && y <= 13;
      px.setAll(p * 4, inside ? [255, 255, 255, 255] : [200, 20, 20, 255]);
    }
    // White corner pixel would win the corner vote's tie-break otherwise.
    px.setAll(0, [255, 255, 255, 255]);
    final out = removeBackground(px, w, h, key: 0xFFC81414, tolerance: 0.05);
    expect(alpha(out, 19, 0), 0);
    expect(alpha(out, 10, 10), 255);
    // The white corner doesn't match red, so it stays.
    expect(alpha(out, 0, 0), 255);
  });

  test('edge pixels close to the background fade out', () {
    final px = Uint8List(w * h * 4);
    for (var p = 0; p < w * h; p++) {
      final x = p % w;
      // Background, then a pale anti-aliasing column, then dark artwork.
      final v = x < 8 ? 255 : (x == 8 ? 225 : 0);
      px.setAll(p * 4, [v, v, v, 255]);
    }
    final out = removeBackground(px, w, h, key: 0xFFFFFFFF, tolerance: 0.1);
    expect(alpha(out, 7, 5), 0);
    final a = alpha(out, 8, 5);
    expect(a, inExclusiveRange(0, 255));
    // Premultiplied: colour shrinks with alpha.
    expect(out[(5 * w + 8) * 4], lessThanOrEqualTo(a));
    expect(alpha(out, 9, 5), 255);
  });

  test('editor stores the result as a new asset and undo restores the original', () async {
    final (ed, dir) = await makeEditor();
    final png = await _png(sample());
    final assetId = 'orig';
    ed.project.assets[assetId] = Asset('image/png', png);
    ed.mutate(() => ed.project.objects.add(ImageObject(id: 'img', name: 'Pic', assetId: assetId, width: 20, height: 20)));
    ed.select(['img']);
    await ed.removeImageBackground(tolerance: 0.1);
    final img = ed.project.byId('img') as ImageObject;
    expect(img.assetId, isNot(assetId));
    expect(ed.project.assets[img.assetId]!.mime, 'image/png');
    final decoded = await _decode(ed.project.assets[img.assetId]!.bytes);
    expect(alpha(decoded, 0, 0), 0);
    expect(alpha(decoded, 9, 9), 255);
    ed.undo();
    expect((ed.project.byId('img') as ImageObject).assetId, assetId);
    ed.dispose();
    await dir.delete(recursive: true);
  });
}

Future<Uint8List> _png(Uint8List rgba) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final d = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  final frame = await (await d.instantiateCodec()).getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}
