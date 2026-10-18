import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/objects.dart';
import '../model/project.dart';
import '../state/editor.dart';
import 'dialogs.dart';
import 'ui_scale.dart';
import 'widgets.dart';

final _recentFonts = <String>[];

/// Editing controls above the canvas. Both rows are always present, even
/// with nothing selected, so the canvas never moves while you work:
///
/// 1. Properties: operation, color, size, position, rotation, arrange.
/// 2. Context: combine tools for shapes, text settings, image tracing, point
///    editing, or a hint for the current tool.
class EditBar extends StatelessWidget {
  const EditBar({super.key, required this.ed, required this.lockRatio, required this.textFocus, required this.textController});

  final EditorController ed;
  final ValueNotifier<bool> lockRatio;
  final FocusNode textFocus;
  final TextEditingController textController;

  /// At 100% interface size; rows grow with it so nothing clips.
  static const rowHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rowHeight = scaled(context, EditBar.rowHeight);
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            FadingRow(height: rowHeight, child: _properties(context)),
            const SizedBox(height: 4),
            FadingRow(height: rowHeight, child: _context(context)),
          ],
        ),
      ),
    );
  }

  Widget _context(BuildContext context) {
    final t = ed.single;
    if (ed.tool == Tool.node && ed.nodeTarget != null) return _node(context);
    if (t is TextObject) return _text(context, t);
    if (ed.textAndPath case (final text, final path)) return _text(context, text, path: path);
    if (t is ImageObject) return _image(context, t);
    if (ed.selection.isNotEmpty) return _combine(context);
    return _hint(context);
  }

  Widget _hint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, text) = switch (ed.tool) {
      Tool.pen => (Icons.draw_outlined, 'Draw freehand. End near the start to make a closed, cuttable shape.'),
      Tool.eraser => (Icons.auto_fix_normal_outlined, 'Drag over shapes to erase. Select shapes first to erase only those.'),
      Tool.crop => (Icons.crop, 'Select what to crop, then drag a rectangle.'),
      Tool.node => (Icons.polyline_outlined, 'Select a shape to edit its points.'),
      Tool.select => (Icons.touch_app_outlined, 'Select something, or add a shape, text or image.'),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        if (ed.tool == Tool.eraser) ...[
          const SizedBox(width: 16),
          const Text('Brush'),
          SizedBox(
            width: scaled(context, 160),
            child: Slider(
              value: ed.eraserWidth,
              min: 0.5,
              max: 25,
              onChanged: (v) {
                ed.eraserWidth = v;
                ed.updateGesture();
              },
            ),
          ),
          Text(formatNumber(ed.project.units.fromMm(ed.eraserWidth), 2) + ed.project.units.suffix),
        ],
      ],
    );
  }

  Widget _properties(BuildContext context) {
    final sel = ed.selected;
    final has = sel.isNotEmpty;
    final u = ed.project.units;
    final b = ed.selectionBounds();
    final first = has ? sel.first : null;
    final sameOp = has && sel.every((o) => o.operation == first!.operation);
    final sameColor = has && sel.every((o) => o.color == first!.color);
    final grouped = sel.any((o) => o.groupId != null);
    final rotation = sel.length == 1 ? first!.xform.rotation * 180 / math.pi : 0.0;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: scaled(context, 150),
          child: DropdownButton<Operation>(
            isExpanded: true,
            value: sameOp ? first!.operation : null,
            hint: Text(has ? 'Mixed' : 'Operation', style: TextStyle(color: scheme.onSurfaceVariant)),
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(8),
            items: [for (final op in Operation.values) DropdownMenuItem(value: op, child: Text(op.label))],
            onChanged: has ? (op) => op == null ? null : ed.setProperty((o) => o.operation = op) : null,
          ),
        ),
        Tooltip(
          message: 'Color (each color cuts on its own mat)',
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: has
                ? () async {
                    final c = await pickColor(context, first!.color);
                    if (c != null) ed.setProperty((o) => o.color = c);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: !has
                  ? Icon(Icons.circle_outlined, color: scheme.outlineVariant)
                  : sameColor
                  ? ColorDot(first!.color, size: 22)
                  : const Icon(Icons.palette_outlined),
            ),
          ),
        ),
        const BarDivider(),
        NumberField(
          label: 'W',
          suffix: u.suffix,
          enabled: has,
          value: b == null ? null : u.fromMm(b.width),
          onChanged: (v) => ed.resizeSelectionTo(width: u.toMm(v), keepRatio: lockRatio.value),
        ),
        ValueListenableBuilder(
          valueListenable: lockRatio,
          builder: (context, locked, _) => ToolButton(
            icon: locked ? Icons.link : Icons.link_off,
            tooltip: locked ? 'Proportions locked (click to unlock)' : 'Proportions unlocked (click to lock)',
            selected: locked,
            onPressed: () => lockRatio.value = !locked,
          ),
        ),
        NumberField(
          label: 'H',
          suffix: u.suffix,
          enabled: has,
          value: b == null ? null : u.fromMm(b.height),
          onChanged: (v) => ed.resizeSelectionTo(height: u.toMm(v), keepRatio: lockRatio.value),
        ),
        const SizedBox(width: 8),
        NumberField(
          label: 'X',
          suffix: u.suffix,
          enabled: has,
          value: b == null ? null : u.fromMm(b.left),
          onChanged: (v) => ed.nudge(Offset(u.toMm(v) - b!.left, 0)),
        ),
        const SizedBox(width: 4),
        NumberField(
          label: 'Y',
          suffix: u.suffix,
          enabled: has,
          value: b == null ? null : u.fromMm(b.top),
          onChanged: (v) => ed.nudge(Offset(0, u.toMm(v) - b!.top)),
        ),
        const SizedBox(width: 4),
        NumberField(
          label: 'Rotate',
          suffix: '°',
          width: 80,
          decimals: 1,
          enabled: has,
          value: has ? rotation : null,
          onChanged: (v) => ed.rotateSelection((v - rotation) * math.pi / 180, b!.center),
        ),
        const BarDivider(),
        PopupMenuButton<AlignMode>(
          enabled: has,
          tooltip: sel.length == 1 ? 'Align to mat' : 'Align',
          icon: const Icon(Icons.align_horizontal_left, size: 20),
          onSelected: ed.align,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: AlignMode.left,
              child: ListTile(leading: Icon(Icons.align_horizontal_left), title: Text('Left')),
            ),
            PopupMenuItem(
              value: AlignMode.centerH,
              child: ListTile(leading: Icon(Icons.align_horizontal_center), title: Text('Center horizontally')),
            ),
            PopupMenuItem(
              value: AlignMode.right,
              child: ListTile(leading: Icon(Icons.align_horizontal_right), title: Text('Right')),
            ),
            PopupMenuItem(
              value: AlignMode.top,
              child: ListTile(leading: Icon(Icons.align_vertical_top), title: Text('Top')),
            ),
            PopupMenuItem(
              value: AlignMode.centerV,
              child: ListTile(leading: Icon(Icons.align_vertical_center), title: Text('Center vertically')),
            ),
            PopupMenuItem(
              value: AlignMode.bottom,
              child: ListTile(leading: Icon(Icons.align_vertical_bottom), title: Text('Bottom')),
            ),
          ],
        ),
        PopupMenuButton<String>(
          enabled: has,
          tooltip: 'Arrange',
          icon: const Icon(Icons.layers_outlined, size: 20),
          onSelected: (v) => switch (v) {
            'front' => ed.toFront(),
            'forward' => ed.reorder(1),
            'backward' => ed.reorder(-1),
            'back' => ed.toBack(),
            'distH' => ed.distribute(horizontal: true),
            'distV' => ed.distribute(horizontal: false),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'front', child: Text('Bring to front')),
            const PopupMenuItem(value: 'forward', child: Text('Bring forward  ⌘]')),
            const PopupMenuItem(value: 'backward', child: Text('Send backward  ⌘[')),
            const PopupMenuItem(value: 'back', child: Text('Send to back')),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'distH', enabled: sel.length > 2, child: const Text('Distribute horizontally')),
            PopupMenuItem(value: 'distV', enabled: sel.length > 2, child: const Text('Distribute vertically')),
          ],
        ),
        ToolButton(icon: Icons.flip, tooltip: 'Flip horizontally (mirror)', onPressed: has ? () => ed.flip(horizontal: true) : null),
        RotatedBox(
          quarterTurns: 1,
          child: ToolButton(icon: Icons.flip, tooltip: 'Flip vertically', onPressed: has ? () => ed.flip(horizontal: false) : null),
        ),
        grouped
            ? ToolButton(icon: Icons.layers_clear_outlined, tooltip: 'Ungroup  ⌘⇧G', onPressed: ed.ungroup)
            : ToolButton(
                icon: Icons.workspaces_outlined,
                tooltip: 'Group (keeps arrangement on the mat)  ⌘G',
                onPressed: sel.length > 1 ? ed.group : null,
              ),
        ToolButton(icon: Icons.copy_all_outlined, tooltip: 'Duplicate  ⌘D', onPressed: has ? ed.duplicate : null),
        ToolButton(icon: Icons.delete_outline, tooltip: 'Delete', onPressed: has ? ed.deleteSelected : null),
      ],
    );
  }

  Widget _combine(BuildContext context) {
    final n = ed.selection.length;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        TextButton.icon(onPressed: n > 1 ? ed.weld : null, icon: const Icon(Icons.join_full, size: 18), label: const Text('Weld')),
        TextButton.icon(onPressed: n == 2 ? ed.slice : null, icon: const Icon(Icons.content_cut, size: 18), label: const Text('Slice')),
        TextButton.icon(
          onPressed: n > 1 ? ed.intersectSelected : null,
          icon: const Icon(Icons.join_inner, size: 18),
          label: const Text('Intersect'),
        ),
        TextButton.icon(onPressed: n > 1 ? ed.subtract : null, icon: const Icon(Icons.join_left, size: 18), label: const Text('Subtract')),
        TextButton.icon(
          onPressed: () => showOffsetDialog(context, ed),
          icon: const Icon(Icons.border_outer, size: 18),
          label: const Text('Offset'),
        ),
        if (ed.single is PathObject)
          TextButton.icon(
            onPressed: () => ed.setTool(Tool.node),
            icon: const Icon(Icons.polyline_outlined, size: 18),
            label: const Text('Edit points'),
          ),
        const SizedBox(width: 8),
        if (n == 1) Text('Select two or more shapes to weld, slice or subtract.', style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  /// [path] is the shape selected along with the text, which it can be put on.
  Widget _text(BuildContext context, TextObject t, {PathObject? path}) {
    final onPath = t.pathId != null;
    if (textController.text != t.text && !textFocus.hasFocus) textController.text = t.text;
    final u = ed.project.units;
    final styles = ed.fonts.stylesOf(t.fontFamily);
    return Row(
      children: [
        SizedBox(
          width: scaled(context, 200),
          child: TextField(
            controller: textController,
            focusNode: textFocus,
            minLines: 1,
            maxLines: 1,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(isDense: true, labelText: 'Text', border: OutlineInputBorder()),
            onChanged: (v) => ed.editText(t, (t) => t.text = v),
          ),
        ),
        IconButton(
          tooltip: 'Edit multi-line text',
          icon: const Icon(Icons.notes, size: 20),
          onPressed: () async {
            final v = await _multilineText(context, t.text);
            if (v != null) ed.editText(t, (t) => t.text = v);
          },
        ),
        OutlinedButton.icon(
          icon: t.fontMissing
              ? const Icon(Icons.warning_amber, color: Colors.orange, size: 18)
              : const Icon(Icons.font_download_outlined, size: 18),
          label: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scaled(context, 140)),
            child: Text(t.fontFamily, overflow: TextOverflow.ellipsis),
          ),
          onPressed: () async {
            final f = await pickFont(context, ed.fonts, current: t.fontFamily, recent: _recentFonts);
            if (f == null) return;
            _recentFonts
              ..remove(f)
              ..insert(0, f);
            if (_recentFonts.length > 8) _recentFonts.removeLast();
            ed.editText(t, (t) {
              t.fontFamily = f;
              final s = ed.fonts.stylesOf(f);
              if (!s.contains(t.fontStyle)) t.fontStyle = s.first;
            });
          },
        ),
        if (styles.length > 1) ...[
          const SizedBox(width: 4),
          DropdownButton<String>(
            value: styles.contains(t.fontStyle) ? t.fontStyle : styles.first,
            underline: const SizedBox(),
            items: [for (final s in styles) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (s) => s == null ? null : ed.editText(t, (t) => t.fontStyle = s),
          ),
        ],
        const SizedBox(width: 8),
        NumberField(
          label: 'Size',
          suffix: u.suffix,
          value: u.fromMm(t.size * t.xform.sy.abs()),
          onChanged: (v) {
            ed.editText(t, (t) => t.size = u.toMm(v) / t.xform.sy.abs());
          },
        ),
        const SizedBox(width: 4),
        NumberField(
          label: 'Spacing',
          value: t.letterSpacing * 100,
          decimals: 0,
          width: 84,
          suffix: '%',
          onChanged: (v) => ed.editText(t, (t) => t.letterSpacing = v / 100),
        ),
        const SizedBox(width: 4),
        NumberField(
          label: 'Line',
          value: t.lineSpacing,
          decimals: 2,
          width: 66,
          onChanged: (v) => ed.editText(t, (t) => t.lineSpacing = v.clamp(0.3, 5)),
        ),
        if (!onPath) ...[
          const SizedBox(width: 8),
          const Text('Curve'),
          SizedBox(
            width: scaled(context, 130),
            child: Slider(
              value: t.curve.clamp(-360, 360),
              min: -360,
              max: 360,
              onChangeStart: (_) => ed.beginGesture(),
              onChanged: (v) {
                t.curve = (v.abs() < 4 ? 0 : v).roundToDouble();
                ed.updateGesture();
              },
              onChangeEnd: (_) => ed.endGesture(),
            ),
          ),
          NumberField(
            value: t.curve,
            decimals: 0,
            width: 76,
            suffix: '°',
            onChanged: (v) => ed.editText(t, (t) => t.curve = v.clamp(-360, 360)),
          ),
        ] else
          ..._pathControls(context, t),
        const SizedBox(width: 8),
        if (onPath)
          TextButton.icon(
            onPressed: () => ed.releaseTextFromPath(t),
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Release from path'),
          ),
        if (!onPath || (path != null && path.id != t.pathId))
          Tooltip(
            message: path == null ? 'Select this text and a shape to lay the text along it' : 'Lay the text along "${path.name}"',
            child: TextButton.icon(
              onPressed: path == null ? null : ed.putTextOnPath,
              icon: const Icon(Icons.gesture_outlined, size: 18),
              label: const Text('Put on path'),
            ),
          ),
        const SizedBox(width: 8),
        SegmentedButton<TextAlign2>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: TextAlign2.left, icon: Icon(Icons.format_align_left, size: 18), tooltip: 'Align left'),
            ButtonSegment(value: TextAlign2.center, icon: Icon(Icons.format_align_center, size: 18), tooltip: 'Center'),
            ButtonSegment(value: TextAlign2.right, icon: Icon(Icons.format_align_right, size: 18), tooltip: 'Align right'),
          ],
          selected: {t.align},
          onSelectionChanged: (s) => ed.editText(t, (t) => t.align = s.first),
        ),
        const SizedBox(width: 4),
        FilterChip(label: const Text('Kerning'), selected: t.useKerning, onSelected: (v) => ed.editText(t, (t) => t.useKerning = v)),
        const SizedBox(width: 8),
        TextButton.icon(onPressed: ed.textToOutlines, icon: const Icon(Icons.gesture, size: 18), label: const Text('To outlines')),
        TextButton.icon(
          onPressed: () => showOffsetDialog(context, ed),
          icon: const Icon(Icons.border_outer, size: 18),
          label: const Text('Offset'),
        ),
        if (t.fontMissing)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text('Font not installed. Showing the saved outline.', style: TextStyle(color: Colors.orange)),
          ),
      ],
    );
  }

  List<Widget> _pathControls(BuildContext context, TextObject t) {
    final u = ed.project.units;
    return [
      const SizedBox(width: 8),
      const Text('Start'),
      SizedBox(
        width: scaled(context, 130),
        child: Slider(
          value: t.pathStart.clamp(0, 1),
          onChangeStart: (_) => ed.beginGesture(),
          onChanged: (v) {
            t.pathStart = v;
            ed.updateGesture();
          },
          onChangeEnd: (_) => ed.endGesture(),
        ),
      ),
      NumberField(
        value: t.pathStart * 100,
        decimals: 0,
        width: 72,
        suffix: '%',
        onChanged: (v) => ed.editText(t, (t) => t.pathStart = (v / 100).clamp(0, 1)),
      ),
      const SizedBox(width: 4),
      NumberField(
        label: 'Offset',
        suffix: u.suffix,
        value: u.fromMm(t.pathOffset),
        onChanged: (v) => ed.editText(t, (t) => t.pathOffset = u.toMm(v)),
      ),
      const SizedBox(width: 4),
      Tooltip(
        message: 'Run the text along the other side of the path (inside a closed shape)',
        child: FilterChip(
          label: const Text('Other side'),
          selected: t.pathFlip,
          onSelected: (v) => ed.editText(t, (t) => t.pathFlip = v),
        ),
      ),
    ];
  }

  Future<String?> _multilineText(BuildContext context, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _image(BuildContext context, ImageObject img) => Row(
    children: [
      FilledButton.tonalIcon(
        onPressed: () => showTraceDialog(context, ed),
        icon: const Icon(Icons.auto_fix_high, size: 18),
        label: Text(img.cutOutline == null ? 'Trace outline' : 'Re-trace'),
      ),
      const SizedBox(width: 8),
      if (img.cutOutline != null) TextButton(onPressed: ed.clearCutOutline, child: const Text('Cut the rectangle instead')),
      TextButton.icon(onPressed: () => ed.setTool(Tool.crop), icon: const Icon(Icons.crop, size: 18), label: const Text('Crop')),
      if (img.crop != null) TextButton(onPressed: () => ed.setProperty((o) => (o as ImageObject).crop = null), child: const Text('Uncrop')),
      TextButton.icon(
        onPressed: () => showRemoveBackgroundDialog(context, ed),
        icon: const Icon(Icons.layers_clear_outlined, size: 18),
        label: const Text('Remove background'),
      ),
      const SizedBox(width: 8),
      Text(
        img.operation == Operation.print
            ? 'Prints, then cuts along the red line.'
            : 'Set the operation to "Print then cut" to print this image.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _node(BuildContext context) {
    final hasNode = ed.activeNode != null;
    return Row(
      children: [
        FilledButton.tonal(onPressed: () => ed.setTool(Tool.select), child: const Text('Done')),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: hasNode ? ed.toggleActiveNodeSmooth : null,
          icon: const Icon(Icons.timeline, size: 18),
          label: const Text('Smooth / corner'),
        ),
        TextButton.icon(
          onPressed: hasNode ? ed.deleteActiveNode : null,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          label: const Text('Delete point'),
        ),
        TextButton.icon(
          onPressed: hasNode ? ed.breakAtActiveNode : null,
          icon: const Icon(Icons.call_split, size: 18),
          label: const Text('Break path'),
        ),
        const SizedBox(width: 8),
        Text(
          'Drag points and handles. Double-tap an outline to add a point.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A horizontally scrolling row that fades at an edge when more content is
/// hidden there, so it's clear the row scrolls.
class FadingRow extends StatefulWidget {
  const FadingRow({super.key, required this.child, required this.height});
  final Widget child;
  final double height;

  @override
  State<FadingRow> createState() => _FadingRowState();
}

class _FadingRowState extends State<FadingRow> {
  final controller = ScrollController();
  bool left = false, right = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(FadingRow old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!mounted || !controller.hasClients) return;
    final p = controller.position;
    final l = p.pixels > 1, r = p.pixels < p.maxScrollExtent - 1;
    if (l != left || r != right) {
      setState(() {
        left = l;
        right = r;
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    Widget fade(Alignment from) => IgnorePointer(
      child: Container(
        width: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: from, end: -from, colors: [bg, bg.withValues(alpha: 0)]),
        ),
      ),
    );
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _update();
                return false;
              },
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(height: widget.height, child: widget.child),
              ),
            ),
          ),
          if (left) Positioned(left: 0, top: 0, bottom: 0, child: fade(Alignment.centerLeft)),
          if (right) Positioned(right: 0, top: 0, bottom: 0, child: fade(Alignment.centerRight)),
        ],
      ),
    );
  }
}
