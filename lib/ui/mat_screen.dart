import 'dart:math' as math;

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../drivers/cutter_driver.dart';
import '../export/pdf_export.dart';
import '../export/svg_export.dart';
import '../mat/mat_planner.dart';
import '../model/objects.dart';
import '../model/project.dart';
import '../platform/platform.dart';
import '../state/editor.dart';
import 'files.dart';
import 'image_cache.dart';
import 'render.dart';
import 'widgets.dart';

/// Lays the design out on mats. Users can drag items anywhere, choose the
/// order mats are cut in, mirror a mat, and export each mat.
class MatScreen extends StatefulWidget {
  const MatScreen({super.key, required this.ed, required this.images});
  final EditorController ed;
  final AssetImages images;

  @override
  State<MatScreen> createState() => _MatScreenState();
}

class _MatScreenState extends State<MatScreen> {
  EditorController get ed => widget.ed;
  MatSettings get s => ed.project.mat;
  String? selectedMat;
  String? selectedItem;

  List<Mat> get mats => planMats(ed.project);

  void _changed() {
    ed.settingsChanged();
    setState(() {});
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _exportMat(Mat mat, CutterDriver d) async {
    final bytes = await d.render(mat, ed.project);
    final name = '${safeFileName(ed.project.meta.name)} - ${safeFileName(mat.label)}.${d.fileExtension}';
    if (await saveBytes(name, bytes, mimeFor(d.fileExtension))) _toast('Saved $name');
  }

  Future<void> _printSheet(Mat mat, {bool save = false}) async {
    final pdf = await exportPrintSheetPdf(mat, ed.project);
    final name = '${safeFileName(ed.project.meta.name)} - print sheet.pdf';
    if (save) {
      if (await saveBytes(name, pdf, 'application/pdf')) _toast('Saved $name. Print at 100% (no scaling).');
    } else {
      await Printing.layoutPdf(onLayout: (_) async => pdf, name: name);
    }
  }

  Future<void> _exportAll(List<Mat> all, CutterDriver d) async {
    if (!hasFileSystem) return _toast('Exporting every mat at once needs the desktop app.');
    final dir = await fp.FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder for the mat files');
    if (dir == null) return;
    final store = FileStore(dir);
    var i = 0;
    for (final m in all) {
      i++;
      final bytes = await d.render(m, ed.project);
      await store.writeAtomic('${i.toString().padLeft(2, '0')} ${safeFileName(m.label)}.${d.fileExtension}', bytes);
      if (m.isPrint) {
        await store.writeAtomic(
          '${i.toString().padLeft(2, '0')} print sheet.pdf',
          await exportPrintSheetPdf(m, ed.project),
        );
      }
    }
    _toast('Saved $i mat file${i == 1 ? '' : 's'} to $dir');
  }

  @override
  Widget build(BuildContext context) {
    final all = mats;
    final scheme = Theme.of(context).colorScheme;
    final current = all.where((m) => m.key == selectedMat).firstOrNull ?? all.firstOrNull;
    final wide = MediaQuery.sizeOf(context).width > 900;
    final side = _side(context, all, current);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prepare mats'),
        actions: [
          PopupMenuButton<CutterDriver>(
            enabled: all.isNotEmpty,
            tooltip: 'Export every mat to a folder',
            onSelected: (d) => _exportAll(all, d),
            itemBuilder: (_) => [
              for (final d in builtInDrivers)
                PopupMenuItem(
                  value: d,
                  child: ListTile(title: Text('All mats as ${d.name}'), subtitle: Text(d.description)),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [Icon(Icons.drive_folder_upload_outlined), SizedBox(width: 6), Text('Export all')]),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: wide ? null : Drawer(width: 320, child: SafeArea(child: side)),
      body: all.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_clear_outlined, size: 48, color: scheme.outline),
                  const SizedBox(height: 12),
                  const Text('Nothing to cut. Hidden layers and guides are skipped.'),
                ],
              ),
            )
          : Row(
              children: [
                if (wide) ...[SizedBox(width: 320, child: side), const VerticalDivider(width: 1)],
                Expanded(child: current == null ? const SizedBox() : _matView(context, current)),
              ],
            ),
    );
  }

  Widget _side(BuildContext context, List<Mat> all, Mat? current) {
    final u = ed.project.units;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Layout', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: s.matSize.name,
          decoration: const InputDecoration(labelText: 'Mat size', isDense: true, border: OutlineInputBorder()),
          items: [for (final m in MatSize.presets) DropdownMenuItem(value: m.name, child: Text(m.name))],
          onChanged: (v) {
            s.matSize = MatSize.presets.firstWhere((m) => m.name == v);
            _changed();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pack to save material'),
          subtitle: const Text('Off keeps your canvas arrangement'),
          value: s.autoPack,
          onChanged: (v) {
            s.autoPack = v;
            _changed();
          },
        ),
        Row(
          children: [
            NumberField(
              label: 'Spacing',
              suffix: u.suffix,
              value: u.fromMm(s.spacing),
              width: 130,
              onChanged: (v) {
                s.spacing = math.max(0, u.toMm(v));
                _changed();
              },
            ),
            const SizedBox(width: 8),
            NumberField(
              label: 'Edge margin',
              suffix: u.suffix,
              value: u.fromMm(s.margin),
              width: 130,
              onChanged: (v) {
                s.margin = math.max(0, u.toMm(v));
                _changed();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Print then Cut', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: s.printSheet.name,
          decoration: const InputDecoration(labelText: 'Paper', isDense: true, border: OutlineInputBorder()),
          items: [
            for (final m in MatSize.presets.where((m) => m.width < 300))
              DropdownMenuItem(value: m.name, child: Text(m.name)),
          ],
          onChanged: (v) {
            s.printSheet = MatSize.presets.firstWhere((m) => m.name == v);
            _changed();
          },
        ),
        const SizedBox(height: 8),
        NumberField(
          label: 'Printer margin',
          suffix: u.suffix,
          value: u.fromMm(s.printMargin),
          width: 140,
          onChanged: (v) {
            s.printMargin = math.max(0, u.toMm(v));
            _changed();
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Usable print area: ${u.fromMm(s.printSheet.width - 2 * (s.printMargin + registrationInset)).toStringAsFixed(2)} × '
            '${u.fromMm(s.printSheet.height - 2 * (s.printMargin + registrationInset)).toStringAsFixed(2)} ${u.suffix}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Mats (cut order)', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (s.order.isNotEmpty)
              TextButton(
                onPressed: () {
                  s.order = [];
                  _changed();
                },
                child: const Text('Reset order'),
              ),
          ],
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final keys = all.map((m) => m.key).toList();
            keys.insert(to, keys.removeAt(from));
            s.order = keys;
            _changed();
          },
          children: [
            for (final (i, m) in all.indexed)
              ListTile(
                key: ValueKey(m.key),
                contentPadding: const EdgeInsets.only(left: 4, right: 4),
                selected: m.key == current?.key,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: () => setState(() {
                  selectedMat = m.key;
                  selectedItem = null;
                }),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator, size: 18)),
                    const SizedBox(width: 4),
                    m.isPrint ? const Icon(Icons.print_outlined, size: 20) : ColorDot(m.color, size: 20),
                  ],
                ),
                title: Text('${i + 1}. ${m.label}'),
                subtitle: Text(
                  '${m.items.length} item${m.items.length == 1 ? '' : 's'}${m.mirror ? ' · mirrored' : ''}',
                ),
                trailing: m.warnings.isNotEmpty
                    ? Tooltip(
                        message: m.warnings.join('\n'),
                        child: const Icon(Icons.warning_amber, color: Colors.orange),
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _matView(BuildContext context, Mat mat) {
    final scheme = Theme.of(context).colorScheme;
    final item = mat.items.where((i) => i.key == selectedItem).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(mat.label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 16),
                  if (!mat.isPrint)
                    FilterChip(
                      avatar: const Icon(Icons.flip, size: 16),
                      label: const Text('Mirror'),
                      tooltip: 'Cut mirrored, for heat-transfer vinyl',
                      selected: mat.mirror,
                      onSelected: (v) {
                        v ? s.mirrored.add(mat.key) : s.mirrored.remove(mat.key);
                        _changed();
                      },
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: mat.items.any((i) => i.manual)
                        ? () {
                            for (final i in mat.items) {
                              s.placements.remove(i.key);
                            }
                            _changed();
                          }
                        : null,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Re-layout this mat'),
                  ),
                  if (item != null) ...[
                    const BarDivider(),
                    Text(item.objects.first.name),
                    TextButton(
                      onPressed: () {
                        s.placements[item.key] = MatPlacement(
                          '${mat.baseKey}#${int.parse(mat.key.split('#').last) + 1}',
                          item.offset,
                        );
                        _changed();
                      },
                      child: const Text('Move to next mat'),
                    ),
                    if (int.parse(mat.key.split('#').last) > 1)
                      TextButton(
                        onPressed: () {
                          s.placements[item.key] = MatPlacement(
                            '${mat.baseKey}#${int.parse(mat.key.split('#').last) - 1}',
                            item.offset,
                          );
                          _changed();
                        },
                        child: const Text('Move to previous mat'),
                      ),
                  ],
                  const BarDivider(),
                  if (mat.isPrint) ...[
                    FilledButton.tonalIcon(
                      onPressed: () => _printSheet(mat),
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Print sheet'),
                    ),
                    const SizedBox(width: 6),
                    TextButton(onPressed: () => _printSheet(mat, save: true), child: const Text('Save sheet PDF')),
                  ],
                  PopupMenuButton<CutterDriver>(
                    tooltip: 'Export this mat',
                    onSelected: (d) => _exportMat(mat, d),
                    itemBuilder: (_) => [
                      for (final d in builtInDrivers)
                        PopupMenuItem(
                          value: d,
                          child: ListTile(title: Text(d.name), subtitle: Text(d.description)),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(children: [Icon(Icons.ios_share, size: 18), SizedBox(width: 6), Text('Export mat')]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (mat.warnings.isNotEmpty)
          MaterialBanner(
            content: Text(mat.warnings.join('\n')),
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            actions: const [SizedBox()],
          ),
        const Divider(height: 1),
        Expanded(
          child: _MatCanvas(
            mat: mat,
            settings: s,
            images: widget.images,
            units: ed.project.units,
            selectedItem: selectedItem,
            onSelect: (k) => setState(() => selectedItem = k),
            onMoved: (item, offset) {
              s.placements[item.key] = MatPlacement(mat.key, offset);
              _changed();
            },
          ),
        ),
        Container(
          color: scheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            mat.mirror
                ? 'Shown face up. This mat is cut mirrored, so place your material face down.'
                : 'Drag items to place them anywhere on the mat. Placed items stay put when you re-open this screen.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _MatCanvas extends StatefulWidget {
  const _MatCanvas({
    required this.mat,
    required this.settings,
    required this.images,
    required this.units,
    required this.selectedItem,
    required this.onSelect,
    required this.onMoved,
  });

  final Mat mat;
  final MatSettings settings;
  final AssetImages images;
  final Units units;
  final String? selectedItem;
  final ValueChanged<String?> onSelect;
  final void Function(MatItem, Offset) onMoved;

  @override
  State<_MatCanvas> createState() => _MatCanvasState();
}

class _MatCanvasState extends State<_MatCanvas> {
  MatItem? dragging;
  Offset dragStart = Offset.zero, itemStart = Offset.zero;
  Offset? liveOffset;

  @override
  void initState() {
    super.initState();
    widget.images.addListener(_repaint);
  }

  @override
  void dispose() {
    widget.images.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final mat = widget.mat;
        const pad = 32.0;
        final scale = math.min((c.maxWidth - pad * 2) / mat.size.width, (c.maxHeight - pad * 2) / mat.size.height);
        final origin = Offset((c.maxWidth - mat.size.width * scale) / 2, (c.maxHeight - mat.size.height * scale) / 2);
        Offset toMat(Offset screen) => (screen - origin) / scale;
        return ClipRect(
          child: GestureDetector(
            onPanStart: (d) {
              final p = toMat(d.localPosition);
              final hit = mat.items.reversed.where((i) => i.rect.inflate(2).contains(p)).firstOrNull;
              widget.onSelect(hit?.key);
              if (hit != null) {
                dragging = hit;
                dragStart = p;
                itemStart = hit.offset;
              }
            },
            onPanUpdate: (d) {
              final it = dragging;
              if (it == null) return;
              final usable = mat.usable(widget.settings);
              var o = itemStart + (toMat(d.localPosition) - dragStart);
              o = Offset(
                o.dx.clamp(usable.left, math.max(usable.left, usable.right - it.size.width)),
                o.dy.clamp(usable.top, math.max(usable.top, usable.bottom - it.size.height)),
              );
              setState(() => liveOffset = o);
            },
            onPanEnd: (_) {
              final it = dragging, o = liveOffset;
              dragging = null;
              liveOffset = null;
              if (it != null && o != null) widget.onMoved(it, o);
            },
            onTapDown: (d) {
              final p = toMat(d.localPosition);
              widget.onSelect(mat.items.reversed.where((i) => i.rect.inflate(2).contains(p)).firstOrNull?.key);
            },
            child: CustomPaint(
              size: c.biggest,
              painter: _MatPainter(
                mat: mat,
                settings: widget.settings,
                images: widget.images,
                scale: scale,
                origin: origin,
                scheme: scheme,
                units: widget.units,
                selected: widget.selectedItem,
                dragging: dragging?.key,
                liveOffset: liveOffset,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MatPainter extends CustomPainter {
  _MatPainter({
    required this.mat,
    required this.settings,
    required this.images,
    required this.scale,
    required this.origin,
    required this.scheme,
    required this.units,
    required this.selected,
    required this.dragging,
    required this.liveOffset,
  });

  final Mat mat;
  final MatSettings settings;
  final AssetImages images;
  final double scale;
  final Offset origin;
  final ColorScheme scheme;
  final Units units;
  final String? selected, dragging;
  final Offset? liveOffset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = scheme.surfaceContainerLow);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final r = Offset.zero & mat.size;
    final hair = 1 / scale;
    canvas.drawRect(r, Paint()..color = mat.isPrint ? Colors.white : const Color(0xFFE9F2EC));
    // Grid every inch (or 10 mm).
    final step = units == Units.inch ? 25.4 : 10.0;
    final grid = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = hair;
    for (var x = step; x < mat.size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, mat.size.height), grid);
    }
    for (var y = step; y < mat.size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(mat.size.width, y), grid);
    }
    canvas.drawRect(
      mat.usable(settings),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hair
        ..color = Colors.black26,
    );
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hair * 1.5
        ..color = Colors.black45,
    );

    if (mat.isPrint) {
      final marks = registrationMarks(mat, settings);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.black;
      final sq = Path()..addPolygon(marks.first, true);
      canvas.drawPath(sq, Paint()..color = Colors.black);
      for (final m in marks.skip(1)) {
        canvas.drawPath(Path()..addPolygon(m, false), p);
      }
    }

    for (final it in mat.items) {
      final off = it.key == dragging && liveOffset != null ? liveOffset! : it.offset;
      canvas.save();
      canvas.translate(off.dx - it.origin.dx, off.dy - it.origin.dy);
      for (final o in it.objects) {
        paintObject(canvas, o, images, scale, opacity: it.key == dragging ? 0.7 : 1);
        if (o is ImageObject) continue;
        if (o.operation != Operation.cut && o.operation != Operation.kissCut) continue;
        // Show the blade path on top of the fill.
        final path = Path();
        for (final pts in o.worldPolylines(0.2)) {
          path.addPolygon(pts, o.localContours.every((c) => c.closed));
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = hair
            ..color = Colors.black54,
        );
      }
      canvas.restore();
      if (it.key == selected) {
        final sr = Rect.fromLTWH(off.dx, off.dy, it.size.width, it.size.height);
        canvas.drawRect(
          sr.inflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * hair
            ..color = scheme.primary,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
