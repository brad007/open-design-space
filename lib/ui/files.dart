import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedFile {
  PickedFile(this.name, this.bytes, this.path);
  final String name;
  final Uint8List bytes;
  final String? path;

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

Future<List<PickedFile>> pickFiles(List<String> extensions, {bool multiple = true, String? title}) async {
  final files = multiple
      ? await FilePicker.pickFiles(dialogTitle: title, type: FileType.custom, allowedExtensions: extensions)
      : [?await FilePicker.pickFile(dialogTitle: title, type: FileType.custom, allowedExtensions: extensions)];
  return [for (final f in files) PickedFile(f.name, await f.readAsBytes(), f.path)];
}

/// Asks where to save and writes the file. Returns false if cancelled.
Future<bool> saveBytes(String fileName, Uint8List bytes, String mimeType) async {
  final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType, dialogTitle: 'Save $fileName');
  return uri != null;
}

String safeFileName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-').trim();
  return cleaned.isEmpty ? 'design' : cleaned;
}

String mimeFor(String ext) => switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'svg' => 'image/svg+xml',
      'pdf' => 'application/pdf',
      'dxf' => 'image/vnd.dxf',
      _ => 'application/octet-stream',
    };
