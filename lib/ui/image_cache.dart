import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/project.dart';

/// Decoded images for a project's assets, decoded once and shared.
class AssetImages extends ChangeNotifier {
  AssetImages(this.project);
  final Project project;
  final _images = <String, ui.Image>{};
  final _pending = <String>{};

  ui.Image? operator [](String assetId) {
    final img = _images[assetId];
    if (img == null && !_pending.contains(assetId)) _decode(assetId);
    return img;
  }

  Future<void> _decode(String id) async {
    final asset = project.assets[id];
    if (asset == null) return;
    _pending.add(id);
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(asset.bytes));
      final frame = await codec.getNextFrame();
      _images[id] = frame.image;
      notifyListeners();
    } catch (_) {
      // Undecodable images render as a placeholder box.
    } finally {
      _pending.remove(id);
    }
  }

  @override
  void dispose() {
    for (final i in _images.values) {
      i.dispose();
    }
    super.dispose();
  }
}
