import 'dart:convert';

import 'package:flutter/material.dart';

import '../platform/platform.dart';

/// The interface size (text and icons), from [UiScale.min] to [UiScale.max].
/// It belongs to this device, not to a project, so it lives in its own small
/// settings file in the app data folder.
class UiScale extends ValueNotifier<double> {
  UiScale([super.value = 1]);

  static const min = 0.9, max = 1.5;
  static const steps = [0.9, 1.0, 1.1, 1.25, 1.5];
  static const _file = 'settings.json';

  FileStore? _store;

  /// Reads the saved size, if any. A missing or damaged file means 100%.
  static Future<UiScale> load() async {
    final s = UiScale();
    try {
      s._store = FileStore(await appDataDir());
      final raw = await s._store!.readString(_file);
      final v = raw == null ? null : (jsonDecode(raw) as Map)['uiScale'];
      if (v is num) s.value = v.toDouble().clamp(min, max);
    } on Object {
      // Fall back to the default size.
    }
    return s;
  }

  Future<void> set(double v) async {
    value = v.clamp(min, max);
    final store = _store;
    if (store == null) return;
    var settings = <String, Object?>{};
    try {
      final raw = await store.readString(_file);
      if (raw != null) settings = Map<String, Object?>.from(jsonDecode(raw) as Map);
    } on Object {
      // Rewrite a damaged file.
    }
    settings['uiScale'] = value;
    await store.writeAtomic(_file, utf8.encode(jsonEncode(settings)));
  }

  static String label(double v) => '${(v * 100).round()}%';
}

/// Scales text and icons below it by [scale], on top of the system text size.
class UiScaleScope extends StatelessWidget {
  const UiScaleScope({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final system = MediaQuery.textScalerOf(context);
    final factor = system.scale(14) / 14 * scale;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(factor)),
      child: IconTheme.merge(data: const IconThemeData(applyTextScaling: true), child: child),
    );
  }
}

/// [v] logical pixels grown with the interface size, for boxes that hold text
/// or icons and would otherwise clip them.
double scaled(BuildContext context, double v) => MediaQuery.textScalerOf(context).scale(v);

/// Makes [scale] reachable from the View menu with [UiScaleHost.of].
class UiScaleHost extends InheritedNotifier<UiScale> {
  const UiScaleHost({super.key, required UiScale scale, required super.child}) : super(notifier: scale);

  static UiScale? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<UiScaleHost>()?.notifier;

  /// For [MaterialApp.builder]: provides [scale] and applies it to the app.
  static Widget wrap(UiScale scale, Widget? child) => UiScaleHost(
        scale: scale,
        child: ListenableBuilder(
          listenable: scale,
          builder: (context, _) => UiScaleScope(scale: scale.value, child: child ?? const SizedBox()),
        ),
      );
}
