import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../geometry/trace.dart';
import '../model/project.dart';
import '../state/editor.dart';
import '../text/font_registry.dart';
import 'ui_scale.dart';

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String? label, String action = 'OK'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: Text(action)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'OK', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

const swatches = [
  0xFF111827, 0xFF6B7280, 0xFFFFFFFF, 0xFFE5484D, 0xFFF76B15, 0xFFF5A524, 0xFFFFE629,
  0xFF30A46C, 0xFF12A594, 0xFF0090FF, 0xFF2F6FED, 0xFF8E4EC6, 0xFFD6409F, 0xFFA18072,
  0xFFC9B458, 0xFFB8B8B8, 0xFF3E63DD, 0xFF00A2C7, 0xFF7CE2B4, 0xFFFFC0CB, 0xFF5B2C06,
];

Future<int?> pickColor(BuildContext context, int current) {
  final hex = TextEditingController(text: (current & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase());
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Color'),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in swatches)
              InkWell(
                onTap: () => Navigator.pop(context, c),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c == current ? Theme.of(context).colorScheme.primary : Colors.black26,
                      width: c == current ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: hex,
            decoration: const InputDecoration(prefixText: '#', labelText: 'Hex'),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), LengthLimitingTextInputFormatter(6)],
            onSubmitted: (v) {
              final n = int.tryParse(v, radix: 16);
              if (n != null && v.length == 6) Navigator.pop(context, 0xFF000000 | n);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(hex.text, radix: 16);
            if (n != null && hex.text.length == 6) Navigator.pop(context, 0xFF000000 | n);
          },
          child: const Text('Use hex'),
        ),
      ],
    ),
  );
}

/// Searchable list of installed and imported fonts, with recent ones first.
Future<String?> pickFont(BuildContext context, FontRegistry fonts, {String? current, List<String> recent = const []}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _FontPicker(fonts: fonts, current: current, recent: recent),
  );
}

class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.fonts, this.current, required this.recent});
  final FontRegistry fonts;
  final String? current;
  final List<String> recent;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.fonts.families;
    final filtered = q.isEmpty ? all : all.where((f) => f.toLowerCase().contains(q.toLowerCase())).toList();
    final recent = q.isEmpty ? widget.recent.where(all.contains).toList() : <String>[];
    return AlertDialog(
      title: const Text('Font'),
      content: SizedBox(
        width: 380,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search ${all.length} fonts'),
            onChanged: (v) => setState(() => q = v),
            onSubmitted: (_) {
              if (filtered.isNotEmpty) Navigator.pop(context, filtered.first);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              if (recent.isNotEmpty) ...[
                const _SectionLabel('Recent'),
                for (final f in recent) _tile(f),
                const _SectionLabel('All fonts'),
              ],
              for (final f in filtered) _tile(f),
              if (filtered.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('No matching fonts. Import a .ttf from the toolbar.')),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }

  Widget _tile(String f) => ListTile(
        dense: true,
        selected: f == widget.current,
        title: Text(f),
        subtitle: Text('${widget.fonts.stylesOf(f).length} styles'),
        onTap: () => Navigator.pop(context, f),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

Future<void> showOffsetDialog(BuildContext context, EditorController ed) async {
  final units = ed.project.units;
  var distance = units == Units.inch ? 0.125 : 3.0;
  var rounded = true;
  var weld = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Offset'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Adds an outline around the selection, for layered designs, borders and stickers. Negative values shrink.'),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: '$distance',
              autofocus: true,
              decoration: InputDecoration(labelText: 'Distance', suffixText: units.suffix),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (v) => distance = double.tryParse(v) ?? distance,
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Rounded')),
                ButtonSegment(value: false, label: Text('Sharp')),
              ],
              selected: {rounded},
              onSelectionChanged: (s) => set(() => rounded = s.first),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: weld,
              onChanged: (v) => set(() => weld = v ?? true),
              title: const Text('One outline around everything'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create offset')),
        ],
      ),
    ),
  );
  if (ok == true) ed.offsetSelected(units.toMm(distance), rounded: rounded, weldResult: weld);
}

Future<void> showTraceDialog(BuildContext context, EditorController ed) async {
  var mode = TraceMode.dark;
  var threshold = 0.5;
  var asCutLine = true;
  var outerOnly = true;
  var offset = 0.0;
  final units = ed.project.units;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Trace image'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<TraceMode>(
              segments: const [
                ButtonSegment(value: TraceMode.dark, label: Text('Dark areas')),
                ButtonSegment(value: TraceMode.opaque, label: Text('Non-transparent')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => set(() => mode = s.first),
            ),
            const SizedBox(height: 12),
            Text('Threshold ${(threshold * 100).round()}%'),
            Slider(value: threshold, min: 0.05, max: 0.95, onChanged: (v) => set(() => threshold = v)),
            TextFormField(
              initialValue: '0',
              decoration: InputDecoration(labelText: 'Grow outline by', suffixText: units.suffix, helperText: 'Adds a sticker border'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (v) => offset = double.tryParse(v) ?? 0,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: outerOnly,
              onChanged: (v) => set(() => outerOnly = v ?? true),
              title: const Text('Outer outline only'),
              subtitle: const Text('Ignore holes inside the artwork'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: asCutLine,
              onChanged: (v) => set(() => asCutLine = v ?? true),
              title: const Text("Use as the image's cut line"),
              subtitle: const Text('Print then Cut along the outline. Off: create a separate shape.'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Trace')),
        ],
      ),
    ),
  );
  if (ok == true) {
    await ed.traceSelectedImage(
      mode: mode,
      threshold: threshold,
      offset: units.toMm(offset),
      asCutLine: asCutLine,
      outerOnly: outerOnly,
    );
  }
}

Future<void> showRemoveBackgroundDialog(BuildContext context, EditorController ed) async {
  int? color;
  var tolerance = 0.15;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: const Text('Remove background'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Clears the colour around the edge of the image. The same colour inside the artwork is kept.'),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Corner colour')),
                ButtonSegment(value: true, label: Text('Pick a colour')),
              ],
              selected: {color != null},
              onSelectionChanged: (s) async {
                if (!s.first) return set(() => color = null);
                final c = await pickColor(context, color ?? 0xFFFFFFFF);
                if (c != null) set(() => color = c);
              },
            ),
            if (color != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: Color(color!), shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
                  ),
                  const SizedBox(width: 8),
                  const Text('Background colour'),
                ]),
              ),
            const SizedBox(height: 12),
            Text('Tolerance ${(tolerance * 100).round()}%'),
            Slider(value: tolerance, min: 0.01, max: 0.6, onChanged: (v) => set(() => tolerance = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    ),
  );
  if (ok == true) await ed.removeImageBackground(color: color, tolerance: tolerance);
}

Future<void> showRestorePoints(BuildContext context, EditorController ed) async {
  final times = await ed.store.snapshots(ed.project.meta.id);
  if (!context.mounted) return;
  final pick = await showDialog<DateTime>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore points'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: times.isEmpty
            ? const Center(child: Text('No restore points yet. They are saved every few minutes while you work, or with ⌘⇧S.'))
            : ListView(children: [
                for (final t in times)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(MaterialLocalizations.of(context).formatMediumDate(t)),
                    subtitle: Text(TimeOfDay.fromDateTime(t).format(context)),
                    onTap: () => Navigator.pop(context, t),
                  ),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.tonal(
          onPressed: () {
            ed.saveRestorePoint();
            Navigator.pop(context);
          },
          child: const Text('Save a restore point now'),
        ),
      ],
    ),
  );
  if (pick == null) return;
  final snap = await ed.store.loadSnapshot(ed.project.meta.id, pick);
  if (snap != null) ed.replaceWithSnapshot(snap);
}

const shortcutHelp = [
  ('V', 'Select tool'),
  ('N', 'Node edit tool'),
  ('P', 'Pen (freehand)'),
  ('E', 'Eraser'),
  ('C', 'Crop'),
  ('T', 'Add text'),
  ('R / O', 'Add square / circle'),
  ('⌘Z / ⌘⇧Z', 'Undo / redo'),
  ('⌘C ⌘X ⌘V', 'Copy, cut, paste'),
  ('⌘D', 'Duplicate'),
  ('⌘A', 'Select all'),
  ('⌘G / ⌘⇧G', 'Group / ungroup'),
  ('⌘W', 'Weld'),
  ('⌘[ / ⌘]', 'Send backward / bring forward'),
  ('Delete', 'Delete selection or node'),
  ('Arrows', 'Nudge 1 mm or 1/16 in (Shift: 10×)'),
  ('⌥ / Alt + arrows', 'Fine nudge: 0.1 mm or 1/100 in'),
  ('⌘0', 'Zoom to fit'),
  ('⌘= / ⌘-', 'Zoom in / out'),
  ('Space + drag', 'Pan'),
  ('Shift + drag corner', 'Toggle proportion lock'),
  ('Shift + rotate', 'Snap to 15°'),
  ('Double-click', 'Edit text or nodes'),
  ('⌘S', 'Save now'),
  ('⌘⇧S', 'Save a restore point'),
  ('⌘M', 'Make it (mat preview)'),
];

/// Lets people make text and icons bigger (or a little smaller). Changes
/// apply as soon as a size is picked.
void showInterfaceSize(BuildContext context, UiScale scale) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Interface size'),
        content: ListenableBuilder(
          listenable: scale,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Makes text and icons bigger on this device. Designs are not affected.'),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in UiScale.steps)
                  ChoiceChip(label: Text(UiScale.label(v)), selected: (scale.value - v).abs() < 0.001, onSelected: (_) => scale.set(v)),
              ]),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );

void showShortcuts(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: SizedBox(
          width: 420,
          height: 480,
          child: ListView(children: [
            for (final (k, v) in shortcutHelp)
              ListTile(
                dense: true,
                leading: SizedBox(
                  width: 150,
                  child: Text(k, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600)),
                ),
                title: Text(v),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );

void showAboutApp(BuildContext context) => showAboutDialog(
      context: context,
      applicationName: 'Open Design Space',
      applicationVersion: '0.1.1',
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/branding/app_icon.png', width: 56, height: 56),
      ),
      applicationLegalese: 'MIT License. An independent, offline-first design tool for cutting machines. '
          'Not affiliated with or endorsed by any cutting-machine manufacturer.',
    );
