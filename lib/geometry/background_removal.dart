import 'dart:math' as math;
import 'dart:typed_data';

/// The background colour of an RGBA image as 0xAARRGGBB: the corner colour
/// the other corners agree with most, so one odd corner doesn't win.
int sampleCornerColor(Uint8List rgba, int width, int height) {
  final corners = [0, width - 1, (height - 1) * width, height * width - 1];
  var best = corners.first;
  var bestScore = double.infinity;
  for (final a in corners) {
    var score = 0.0;
    for (final b in corners) {
      score += _distance(rgba, a * 4, _argbAt(rgba, b));
    }
    if (score < bestScore) {
      bestScore = score;
      best = a;
    }
  }
  return _argbAt(rgba, best);
}

int _argbAt(Uint8List rgba, int pixel) {
  final i = pixel * 4;
  return rgba[i + 3] << 24 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
}

/// Colour distance from the pixel at byte [i] to [argb], 0 (same) to 1
/// (black against white). Transparent pixels match only transparent keys.
double _distance(Uint8List rgba, int i, int argb) {
  final da = (rgba[i + 3] - (argb >> 24 & 0xFF)) / 255;
  final dr = (rgba[i] - (argb >> 16 & 0xFF)) / 255;
  final dg = (rgba[i + 1] - (argb >> 8 & 0xFF)) / 255;
  final db = (rgba[i + 2] - (argb & 0xFF)) / 255;
  return math.sqrt((dr * dr + dg * dg + db * db + da * da * 3) / 3);
}

/// Makes the background of an RGBA image transparent and returns a new image.
///
/// The background is every pixel within [tolerance] (0–1) of [key] that
/// connects to the image edge through other such pixels, so the same colour
/// enclosed by the artwork (the white inside a letter O) stays. [key]
/// defaults to [sampleCornerColor]. Pixels already transparent count as
/// background. Pixels bordering the removed area fade out over a second
/// tolerance band to soften the edge.
///
/// [rgba] is premultiplied, as Flutter's `rawRgba` decodes it, and so is the
/// result: a faded pixel scales all four channels.
Uint8List removeBackground(Uint8List rgba, int width, int height, {int? key, double tolerance = 0.15}) {
  final out = Uint8List.fromList(rgba);
  final n = width * height;
  if (n == 0) return out;
  final bg = key ?? sampleCornerColor(rgba, width, height);
  final tol = tolerance.clamp(0.0, 1.0);

  bool matches(int p) => rgba[p * 4 + 3] == 0 || _distance(rgba, p * 4, bg) <= tol;

  // Flood fill from every edge pixel that matches.
  final removed = Uint8List(n);
  final stack = <int>[];
  void seed(int p) {
    if (removed[p] == 0 && matches(p)) {
      removed[p] = 1;
      stack.add(p);
    }
  }

  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % width;
    if (x > 0) seed(p - 1);
    if (x < width - 1) seed(p + 1);
    if (p >= width) seed(p - width);
    if (p < n - width) seed(p + width);
  }

  for (var p = 0; p < n; p++) {
    final i = p * 4;
    if (removed[p] == 1) {
      out[i] = out[i + 1] = out[i + 2] = out[i + 3] = 0;
      continue;
    }
    // Soften the edge: a kept pixel next to the background that is still
    // close to its colour keeps only part of its opacity.
    final x = p % width;
    final touches = (x > 0 && removed[p - 1] == 1) ||
        (x < width - 1 && removed[p + 1] == 1) ||
        (p >= width && removed[p - width] == 1) ||
        (p < n - width && removed[p + width] == 1);
    if (!touches || tol == 0) continue;
    final f = ((_distance(rgba, i, bg) - tol) / tol).clamp(0.0, 1.0);
    if (f >= 1) continue;
    for (var k = 0; k < 4; k++) {
      out[i + k] = (out[i + k] * f).round();
    }
  }
  return out;
}
