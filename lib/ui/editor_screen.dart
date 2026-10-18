import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../export/pdf_export.dart';
import '../export/svg_export.dart';
import '../geometry/shapes.dart';
import '../model/objects.dart';
import '../model/project.dart';
import '../state/editor.dart';
import '../storage/project_store.dart';
import '../text/font_registry.dart';
import 'canvas_view.dart';
import 'dialogs.dart';
import 'edit_bar.dart';
import 'files.dart';
import 'image_cache.dart';
import 'layers_panel.dart';
import 'library_screen.dart';
import 'mat_screen.dart';
import 'render.dart';
import 'widgets.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project, required this.store, required this.fonts, this.isNew = false});

  final Project project;
  final ProjectStore store;
  final FontRegistry fonts;
  final bool isNew;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController ed;
  late final AssetImages images;
  final vp = CanvasViewport();
  final lockRatio = ValueNotifier(true);
  final textFocus = FocusNode();
  final textController = TextEditingController();
  final screenFocus = FocusNode(debugLabel: 'editor');
  bool showLayers = true;
  final cursor = ValueNotifier<Offset?>(null);

  @override
  void initState() {
    super.initState();
    ed = EditorController(project: widget.project, store: widget.store, fonts: widget.fonts, onDisk: !widget.isNew);
    images = AssetImages(widget.project);
    ed.thumbnailBuilder = () => renderPng(ed.project.objects, images, const Size(360, 270));
    ed.addListener(_onChange);
    widget.fonts.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ed.project.objects.isEmpty) {
        final m = ed.project.mat.matSize;
        vp.fit(Rect.fromLTWH(0, 0, m.width, m.height));
      } else {
        vp.fit(ed.contentBounds());
      }
    });
  }

  @override
  void dispose() {
    ed.removeListener(_onChange);
    widget.fonts.removeListener(_onChange);
    if (ed.dirty) ed.save();
    ed.dispose();
    images.dispose();
    textFocus.dispose();
    textController.dispose();
    screenFocus.dispose();
    cursor.dispose();
    super.dispose();
  }

  void _onChange() {
    ed.insertionPoint = vp.size.isEmpty ? ed.insertionPoint : vp.worldCenter;
    setState(() {});
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    var found = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is EditableText) found = true;
      return !found;
    });
    return found;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_typing) {
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        FocusManager.instance.primaryFocus?.unfocus();
        screenFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final k = HardwareKeyboard.instance;
    final cmd = k.isMetaPressed || k.isControlPressed;
    final shift = k.isShiftPressed;
    final key = e.logicalKey;
    bool run(VoidCallback f) {
      f();
      return true;
    }

    final step = shift ? 10.0 : 1.0;
    final unit = ed.project.units == Units.inch ? 25.4 / 16 : 1.0;
    final handled = switch (key) {
      LogicalKeyboardKey.keyZ when cmd && shift => run(ed.redo),
      LogicalKeyboardKey.keyZ when cmd => run(ed.undo),
      LogicalKeyboardKey.keyY when cmd => run(ed.redo),
      LogicalKeyboardKey.keyC when cmd => run(ed.copy),
      LogicalKeyboardKey.keyX when cmd => run(ed.cut),
      LogicalKeyboardKey.keyV when cmd => run(ed.paste),
      LogicalKeyboardKey.keyD when cmd => run(ed.duplicate),
      LogicalKeyboardKey.keyA when cmd => run(ed.selectAll),
      LogicalKeyboardKey.keyG when cmd && shift => run(ed.ungroup),
      LogicalKeyboardKey.keyG when cmd => run(ed.group),
      LogicalKeyboardKey.keyW when cmd => run(ed.weld),
      LogicalKeyboardKey.keyS when cmd && shift => run(ed.saveRestorePoint),
      LogicalKeyboardKey.keyS when cmd => run(ed.save),
      LogicalKeyboardKey.keyM when cmd => run(_makeIt),
      LogicalKeyboardKey.bracketLeft when cmd => run(() => ed.reorder(-1)),
      LogicalKeyboardKey.bracketRight when cmd => run(() => ed.reorder(1)),
      LogicalKeyboardKey.digit0 when cmd => run(_fit),
      LogicalKeyboardKey.equal when cmd => run(() => vp.zoomAt(vp.size.center(Offset.zero), 1.25)),
      LogicalKeyboardKey.minus when cmd => run(() => vp.zoomAt(vp.size.center(Offset.zero), 0.8)),
      LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace =>
        run(() => ed.tool == Tool.node && ed.activeNode != null ? ed.deleteActiveNode() : ed.deleteSelected()),
      LogicalKeyboardKey.escape => run(() {
          if (ed.tool != Tool.select) {
            ed.setTool(Tool.select);
          } else {
            ed.clearSelection();
          }
        }),
      LogicalKeyboardKey.arrowLeft => run(() => ed.nudge(Offset(-step * unit, 0))),
      LogicalKeyboardKey.arrowRight => run(() => ed.nudge(Offset(step * unit, 0))),
      LogicalKeyboardKey.arrowUp => run(() => ed.nudge(Offset(0, -step * unit))),
      LogicalKeyboardKey.arrowDown => run(() => ed.nudge(Offset(0, step * unit))),
      LogicalKeyboardKey.keyV when !cmd => run(() => ed.setTool(Tool.select)),
      LogicalKeyboardKey.keyN when !cmd => run(() => ed.setTool(Tool.node)),
      LogicalKeyboardKey.keyP when !cmd => run(() => ed.setTool(Tool.pen)),
      LogicalKeyboardKey.keyE when !cmd => run(() => ed.setTool(Tool.eraser)),
      LogicalKeyboardKey.keyC when !cmd => run(() => ed.setTool(Tool.crop)),
      LogicalKeyboardKey.keyT when !cmd => run(_addText),
      LogicalKeyboardKey.keyR when !cmd => run(() => ed.addShape(ShapeKind.square)),
      LogicalKeyboardKey.keyO when !cmd => run(() => ed.addShape(ShapeKind.circle)),
      _ => false,
    };
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _fit() => vp.fit(ed.project.objects.any((o) => o.visible) ? ed.contentBounds() : Rect.fromLTWH(0, 0, ed.project.mat.matSize.width, ed.project.mat.matSize.height));

  void _addText() {
    ed.addText();
    final t = ed.single;
    if (t is TextObject) _editText(t);
  }

  void _editText(TextObject t) {
    textController.text = t.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      textFocus.requestFocus();
      textController.selection = TextSelection(baseOffset: 0, extentOffset: t.text.length);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _import(String what) async {
    switch (what) {
      case 'image':
        for (final f in await pickFiles(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'], title: 'Import images')) {
          await ed.addImage(f.bytes, mimeFor(f.extension), f.name);
        }
      case 'svg':
        for (final f in await pickFiles(['svg'], title: 'Import SVG')) {
          try {
            ed.addSvg(utf8.decode(f.bytes, allowMalformed: true), f.name);
          } on FormatException catch (e) {
            _toast('${f.name}: ${e.message}');
          }
        }
      case 'font':
        for (final f in await pickFiles(['ttf', 'ttc'], title: 'Import fonts')) {
          final fams = await ed.fonts.importFontBytes(f.bytes, f.name);
          _toast(fams.isEmpty ? "${f.name} isn't a TrueType font this app can read." : 'Added ${fams.join(', ')}');
        }
    }
  }

  Future<void> _export(String what) async {
    if (ed.project.objects.every((o) => !o.visible)) return _toast('Nothing to export yet.');
    final name = safeFileName(ed.project.meta.name);
    var ok = false;
    switch (what) {
      case 'svg':
        ok = await saveBytes('$name.svg', utf8.encode(exportDesignSvg(ed.project)), 'image/svg+xml');
      case 'pdf':
        ok = await saveBytes('$name.pdf', await exportDesignPdf(ed.project), 'application/pdf');
      case 'png':
        final png = await exportDesignPng(ed.project, images);
        if (png != null) ok = await saveBytes('$name.png', png, 'image/png');
      case 'odsx':
        ok = await saveBytes('$name.$projectExtension', utf8.encode(ed.project.encode()), 'application/json');
    }
    if (ok) _toast('Exported');
  }

  Future<void> _makeIt() async {
    await ed.save();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatScreen(ed: ed, images: images)));
    setState(() {});
  }

  Future<void> _openLibrary() async {
    await ed.save();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LibraryScreen(store: widget.store, fonts: widget.fonts)),
      (_) => false,
    );
  }

  String get _saveLabel {
    if (ed.saving) return 'Saving…';
    if (!ed.onDisk && ed.project.objects.isEmpty) return 'New canvas';
    if (ed.dirty) return 'Unsaved changes';
    final t = ed.lastSaved;
    return t == null ? 'Saved' : 'Saved ${TimeOfDay.fromDateTime(t).format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > 900;
    final compact = width < 760;
    return Focus(
      focusNode: screenFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(tooltip: 'Projects', icon: const Icon(Icons.grid_view_rounded), onPressed: _openLibrary),
          title: Row(children: [
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  final n = await promptText(context, title: 'Project name', initial: ed.project.meta.name, action: 'Rename');
                  if (n != null && n.trim().isNotEmpty) {
                    ed.project.meta.name = n.trim();
                    ed.settingsChanged();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(ed.project.meta.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (compact)
              Tooltip(
                message: _saveLabel,
                child: Icon(ed.dirty || ed.saving ? Icons.cloud_sync_outlined : Icons.cloud_done_outlined, size: 18, color: scheme.onSurfaceVariant),
              )
            else
              Text(_saveLabel, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
          actions: compact ? _compactActions(context) : _wideActions(context),
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
          EditBar(ed: ed, lockRatio: lockRatio, textFocus: textFocus, textController: textController),
          const Divider(height: 1),
          Expanded(
            child: Row(children: [
              _toolRail(context),
              const VerticalDivider(width: 1),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: CanvasView(
                      editor: ed,
                      images: images,
                      viewport: vp,
                      lockRatio: lockRatio,
                      onEditText: _editText,
                      onCursor: (w) => cursor.value = w,
                    ),
                  ),
                  if (ed.project.objects.isEmpty) const _EmptyHint(),
                ]),
              ),
              if (showLayers && wide) ...[
                const VerticalDivider(width: 1),
                SizedBox(width: 260, child: LayersPanel(ed: ed)),
              ],
            ]),
          ),
          const Divider(height: 1),
          _statusBar(context),
        ]),
        ),
        endDrawer: wide ? null : Drawer(child: SafeArea(child: LayersPanel(ed: ed))),
      ),
    );
  }

  void _viewAction(String v) {
    switch (v) {
      case 'fit':
        _fit();
      case 'grid':
        ed.showGrid = !ed.showGrid;
      case 'snap':
        ed.snapping = !ed.snapping;
      case 'units':
        ed.project.units = ed.project.units == Units.inch ? Units.mm : Units.inch;
        ed.settingsChanged();
      case 'layers':
        showLayers = !showLayers;
      case 'history':
        showRestorePoints(context, ed);
      case 'shortcuts':
        showShortcuts(context);
      case 'svg' || 'pdf' || 'png' || 'odsx':
        _export(v);
    }
    setState(() {});
  }

  List<PopupMenuEntry<String>> _viewItems({required bool includeLayers}) => [
        CheckedPopupMenuItem(value: 'grid', checked: ed.showGrid, child: const Text('Grid')),
        CheckedPopupMenuItem(value: 'snap', checked: ed.snapping, child: const Text('Snap to objects and mat')),
        if (includeLayers) CheckedPopupMenuItem(value: 'layers', checked: showLayers, child: const Text('Layers panel')),
        PopupMenuItem(value: 'units', child: Text(ed.project.units == Units.inch ? 'Use millimetres' : 'Use inches')),
      ];

  static const _exportItems = [
    PopupMenuItem(value: 'svg', child: ListTile(leading: Icon(Icons.polyline_outlined), title: Text('SVG'), subtitle: Text('Vector, for any design or cutting app'))),
    PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF'), subtitle: Text('Vector at actual size'))),
    PopupMenuItem(value: 'png', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('PNG'), subtitle: Text('300 dpi image'))),
    PopupMenuItem(value: 'odsx', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Project file (.odsx)'), subtitle: Text('Back up or move to another device'))),
  ];

  List<Widget> _wideActions(BuildContext context) => [
        IconButton(tooltip: 'Undo  ⌘Z', icon: const Icon(Icons.undo), onPressed: ed.canUndo ? ed.undo : null),
        IconButton(tooltip: 'Redo  ⌘⇧Z', icon: const Icon(Icons.redo), onPressed: ed.canRedo ? ed.redo : null),
        const BarDivider(),
        IconButton(tooltip: 'Zoom to fit  ⌘0', icon: const Icon(Icons.fit_screen_outlined), onPressed: _fit),
        PopupMenuButton<String>(
          tooltip: 'View',
          icon: const Icon(Icons.tune),
          onSelected: _viewAction,
          itemBuilder: (_) => _viewItems(includeLayers: MediaQuery.sizeOf(context).width > 900),
        ),
        IconButton(tooltip: 'Restore points', icon: const Icon(Icons.history), onPressed: () => showRestorePoints(context, ed)),
        PopupMenuButton<String>(tooltip: 'Export', icon: const Icon(Icons.ios_share), onSelected: _viewAction, itemBuilder: (_) => _exportItems),
        IconButton(tooltip: 'Keyboard shortcuts', icon: const Icon(Icons.keyboard_outlined), onPressed: () => showShortcuts(context)),
        if (MediaQuery.sizeOf(context).width <= 900)
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Layers',
              icon: const Icon(Icons.layers_outlined),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: _makeIt, icon: const Icon(Icons.content_cut), label: const Text('Make it')),
        const SizedBox(width: 12),
      ];

  List<Widget> _compactActions(BuildContext context) => [
        IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: ed.canUndo ? ed.undo : null),
        IconButton(tooltip: 'Redo', icon: const Icon(Icons.redo), onPressed: ed.canRedo ? ed.redo : null),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: _viewAction,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'fit', child: ListTile(leading: Icon(Icons.fit_screen_outlined), title: Text('Zoom to fit'))),
            const PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Restore points'))),
            const PopupMenuDivider(),
            ..._viewItems(includeLayers: false),
            const PopupMenuDivider(),
            ..._exportItems,
          ],
        ),
        if (MediaQuery.sizeOf(context).width <= 900)
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Layers',
              icon: const Icon(Icons.layers_outlined),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        IconButton.filled(tooltip: 'Make it', icon: const Icon(Icons.content_cut), onPressed: _makeIt),
        const SizedBox(width: 8),
      ];

  Widget _toolRail(BuildContext context) {
    Widget tool(Tool t, IconData i, String tip) => ToolButton(icon: i, tooltip: tip, selected: ed.tool == t, onPressed: () => ed.setTool(t));
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 56,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            tool(Tool.select, Icons.near_me_outlined, 'Select  V'),
            tool(Tool.node, Icons.polyline_outlined, 'Edit points  N'),
            tool(Tool.pen, Icons.draw_outlined, 'Pen  P'),
            tool(Tool.eraser, Icons.auto_fix_normal_outlined, 'Eraser  E'),
            tool(Tool.crop, Icons.crop, 'Crop  C'),
            const Divider(indent: 12, endIndent: 12),
            PopupMenuButton<ShapeKind>(
              tooltip: 'Shapes',
              icon: const Icon(Icons.category_outlined),
              onSelected: ed.addShape,
              itemBuilder: (_) => [for (final k in ShapeKind.values) PopupMenuItem(value: k, child: Text(k.label))],
            ),
            ToolButton(icon: Icons.text_fields, tooltip: 'Text  T', onPressed: _addText),
            PopupMenuButton<String>(
              tooltip: 'Import',
              icon: const Icon(Icons.file_upload_outlined),
              onSelected: _import,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Image'), subtitle: Text('PNG, JPG, GIF, WebP'))),
                PopupMenuItem(value: 'svg', child: ListTile(leading: Icon(Icons.polyline_outlined), title: Text('SVG'))),
                PopupMenuItem(value: 'font', child: ListTile(leading: Icon(Icons.font_download_outlined), title: Text('Font'), subtitle: Text('TrueType .ttf / .ttc'))),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = ed.project.units;
    final style = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Container(
      height: 28,
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Expanded(child: Text(ed.status ?? (ed.fonts.ready ? '' : 'Loading fonts…'), style: style, overflow: TextOverflow.ellipsis)),
        ValueListenableBuilder(
          valueListenable: cursor,
          builder: (context, c, _) => c == null
              ? const SizedBox()
              : Text('${u.fromMm(c.dx).toStringAsFixed(2)}, ${u.fromMm(c.dy).toStringAsFixed(2)} ${u.suffix}', style: style),
        ),
        const SizedBox(width: 16),
        ListenableBuilder(
          listenable: vp,
          builder: (context, _) => Text('${(vp.zoom / (96 / 25.4) * 100).round()}%', style: style),
        ),
        const SizedBox(width: 16),
        Text('${ed.selection.length} selected', style: style),
      ]),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.85),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: scheme.inverseSurface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
          child: Text(
            'Blank canvas. Add text, a shape or an image with the tools on the left. Everything saves on this device.',
            style: TextStyle(color: scheme.onInverseSurface),
          ),
        ),
      ),
    );
  }
}
