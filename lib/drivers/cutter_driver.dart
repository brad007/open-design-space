import 'dart:convert';
import 'dart:typed_data';

import '../export/plotter_export.dart';
import '../export/svg_export.dart';
import '../mat/mat_planner.dart';
import '../model/project.dart';

/// Something that can receive a mat: a file format today, a machine later.
///
/// Machine drivers are deliberately kept out of this repository. A driver
/// for a specific cutter can implement this interface in its own package.
abstract class CutterDriver {
  String get name;
  String get fileExtension;
  String get description;

  /// Produces the bytes to save or send for [mat].
  Future<Uint8List> render(Mat mat, Project project);
}

class SvgDriver implements CutterDriver {
  @override
  String get name => 'SVG';
  @override
  String get fileExtension => 'svg';
  @override
  String get description => 'Open with most cutting software, Inkscape or a browser.';
  @override
  Future<Uint8List> render(Mat mat, Project project) async =>
      Uint8List.fromList(utf8.encode(exportMatSvg(mat, project.mat)));
}

class DxfDriver implements CutterDriver {
  @override
  String get name => 'DXF';
  @override
  String get fileExtension => 'dxf';
  @override
  String get description => 'For CAD/CAM tools, laser and CNC software.';
  @override
  Future<Uint8List> render(Mat mat, Project project) async =>
      Uint8List.fromList(utf8.encode(exportMatDxf(mat)));
}

class HpglDriver implements CutterDriver {
  @override
  String get name => 'HPGL';
  @override
  String get fileExtension => 'plt';
  @override
  String get description => 'For generic plotters and vinyl cutters that accept HPGL.';
  @override
  Future<Uint8List> render(Mat mat, Project project) async =>
      Uint8List.fromList(utf8.encode(exportMatHpgl(mat)));
}

final builtInDrivers = <CutterDriver>[SvgDriver(), DxfDriver(), HpglDriver()];
