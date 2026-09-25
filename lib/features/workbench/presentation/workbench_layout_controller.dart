import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class WorkbenchLayout {
  const WorkbenchLayout({
    this.paletteWidth = 250,
    this.runtimeWidth = 420,
    this.commandOutputFraction = .42,
    this.highRefreshMode = true,
    this.reduceMotion = false,
  });

  final double paletteWidth;
  final double runtimeWidth;
  final double commandOutputFraction;
  final bool highRefreshMode;
  final bool reduceMotion;

  WorkbenchLayout copyWith({
    double? paletteWidth,
    double? runtimeWidth,
    double? commandOutputFraction,
    bool? highRefreshMode,
    bool? reduceMotion,
  }) => WorkbenchLayout(
    paletteWidth: paletteWidth ?? this.paletteWidth,
    runtimeWidth: runtimeWidth ?? this.runtimeWidth,
    commandOutputFraction: commandOutputFraction ?? this.commandOutputFraction,
    highRefreshMode: highRefreshMode ?? this.highRefreshMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );
}

final workbenchLayoutProvider =
    StateNotifierProvider<WorkbenchLayoutController, WorkbenchLayout>(
      (ref) => WorkbenchLayoutController(),
    );

class WorkbenchLayoutController extends StateNotifier<WorkbenchLayout> {
  WorkbenchLayoutController({Future<File> Function()? storageFile})
    : _storageFile = storageFile ?? _defaultStorageFile,
      super(const WorkbenchLayout()) {
    _restoreFuture = _restore();
  }

  final Future<File> Function() _storageFile;
  late final Future<void> _restoreFuture;
  Timer? _saveDebounce;

  Future<void> get restored => _restoreFuture;

  void setPaletteWidth(double width) {
    final value = width.clamp(200.0, 520.0).toDouble();
    if (state.paletteWidth == value) return;
    state = state.copyWith(paletteWidth: value);
    _scheduleSave();
  }

  void setRuntimeWidth(double width) {
    final value = width.clamp(260.0, 720.0).toDouble();
    if (state.runtimeWidth == value) return;
    state = state.copyWith(runtimeWidth: value);
    _scheduleSave();
  }

  void setCommandOutputFraction(double fraction) {
    final value = fraction.clamp(.18, .78).toDouble();
    if (state.commandOutputFraction == value) return;
    state = state.copyWith(commandOutputFraction: value);
    _scheduleSave();
  }

  void setHighRefreshMode(bool enabled) {
    if (state.highRefreshMode == enabled) return;
    state = state.copyWith(highRefreshMode: enabled);
    _scheduleSave();
  }

  void setReduceMotion(bool enabled) {
    if (state.reduceMotion == enabled) return;
    state = state.copyWith(reduceMotion: enabled);
    _scheduleSave();
  }

  void reset() {
    state = const WorkbenchLayout();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), _persist);
  }

  Future<void> _restore() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return;
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      state = WorkbenchLayout(
        paletteWidth: (decoded['paletteWidth'] as num?)?.toDouble() ?? 250,
        runtimeWidth: (decoded['runtimeWidth'] as num?)?.toDouble() ?? 420,
        commandOutputFraction:
            (decoded['commandOutputFraction'] as num?)?.toDouble() ?? .42,
        highRefreshMode: decoded['highRefreshMode'] as bool? ?? true,
        reduceMotion: decoded['reduceMotion'] as bool? ?? false,
      );
    } catch (_) {
      // A corrupt desktop preference file must never prevent opening NodeQL.
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _storageFile();
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'paletteWidth': state.paletteWidth,
          'runtimeWidth': state.runtimeWidth,
          'commandOutputFraction': state.commandOutputFraction,
          'highRefreshMode': state.highRefreshMode,
          'reduceMotion': state.reduceMotion,
        }),
        flush: true,
      );
    } catch (_) {
      // Layout persistence is a convenience, not a condition for working.
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  static Future<File> _defaultStorageFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/nodeql_workbench_layout.json');
  }
}
