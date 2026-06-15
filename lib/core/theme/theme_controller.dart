import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum NodeQlTheme { light, dark, midnight, matrix }

final nodeQlThemeProvider =
    StateNotifierProvider<NodeQlThemeController, NodeQlTheme>(
      (_) => NodeQlThemeController(),
    );

class NodeQlThemeController extends StateNotifier<NodeQlTheme> {
  NodeQlThemeController() : super(NodeQlTheme.dark) {
    _restore();
  }

  Future<void> setTheme(NodeQlTheme theme) async {
    if (state == theme) return;
    state = theme;
    await _persist(theme);
  }

  Future<void> _restore() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final name = '${decoded['theme'] ?? ''}';
      final matched = NodeQlTheme.values.where((t) => t.name == name);
      if (matched.isNotEmpty) {
        state = matched.first;
      }
    } catch (_) {}
  }

  Future<void> _persist(NodeQlTheme theme) async {
    try {
      final file = await _storageFile();
      final payload = <String, dynamic>{
        'theme': theme.name,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<File> _storageFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/nodeql_theme.json');
  }
}

ThemeData themeFor(NodeQlTheme theme) {
  switch (theme) {
    case NodeQlTheme.light:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1D4ED8),
          secondary: Color(0xFF0369A1),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          outline: Color(0xFFCBD5E1),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFFFFFFF),
        ),
        dividerColor: const Color(0xFFCBD5E1),
        extensions: const <ThemeExtension<dynamic>>[
          NodeQlWorkbenchColors.light,
        ],
      );
    case NodeQlTheme.dark:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF22D3EE),
          surface: Color(0xFF0F172A),
          onSurface: Color(0xFFF8FAFC),
        ),
        extensions: const <ThemeExtension<dynamic>>[NodeQlWorkbenchColors.dark],
      ).copyWith(
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFF8FAFC),
          displayColor: const Color(0xFFF8FAFC),
        ),
      );
    case NodeQlTheme.midnight:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05121E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0A1A2A),
          onSurface: Color(0xFFF0F9FF),
        ),
        extensions: const <ThemeExtension<dynamic>>[
          NodeQlWorkbenchColors.midnight,
        ],
      );
    case NodeQlTheme.matrix:
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040B05),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22C55E),
          secondary: Color(0xFF16A34A),
          surface: Color(0xFF07130A),
          onSurface: Color(0xFFD1FAE5),
        ),
        extensions: const <ThemeExtension<dynamic>>[
          NodeQlWorkbenchColors.matrix,
        ],
      );
  }
}

@immutable
class NodeQlWorkbenchColors extends ThemeExtension<NodeQlWorkbenchColors> {
  const NodeQlWorkbenchColors({
    required this.topBar,
    required this.topBarForeground,
    required this.panel,
    required this.panelElevated,
    required this.workspace,
    required this.border,
    required this.muted,
    required this.sqlText,
  });

  static const light = NodeQlWorkbenchColors(
    topBar: Color(0xFFFFFFFF),
    topBarForeground: Color(0xFF0F172A),
    panel: Color(0xFFF8FAFC),
    panelElevated: Color(0xFFFFFFFF),
    workspace: Color(0xFFE2E8F0),
    border: Color(0xFFCBD5E1),
    muted: Color(0xFF64748B),
    sqlText: Color(0xFF075985),
  );

  static const dark = NodeQlWorkbenchColors(
    topBar: Color(0xFF0B1220),
    topBarForeground: Color(0xFFE2E8F0),
    panel: Color(0xFF0F172A),
    panelElevated: Color(0xFF111C30),
    workspace: Color(0xFF111827),
    border: Color(0xFF1E293B),
    muted: Color(0xFF94A3B8),
    sqlText: Color(0xFFBDE0FE),
  );

  static const midnight = NodeQlWorkbenchColors(
    topBar: Color(0xFF05121E),
    topBarForeground: Color(0xFFF0F9FF),
    panel: Color(0xFF0A1A2A),
    panelElevated: Color(0xFF0D2438),
    workspace: Color(0xFF071827),
    border: Color(0xFF164E63),
    muted: Color(0xFF7DD3FC),
    sqlText: Color(0xFFBAE6FD),
  );

  static const matrix = NodeQlWorkbenchColors(
    topBar: Color(0xFF040B05),
    topBarForeground: Color(0xFFD1FAE5),
    panel: Color(0xFF07130A),
    panelElevated: Color(0xFF0A1F0E),
    workspace: Color(0xFF061009),
    border: Color(0xFF14532D),
    muted: Color(0xFF86EFAC),
    sqlText: Color(0xFFBBF7D0),
  );

  static NodeQlWorkbenchColors of(BuildContext context) {
    return Theme.of(context).extension<NodeQlWorkbenchColors>() ?? dark;
  }

  final Color topBar;
  final Color topBarForeground;
  final Color panel;
  final Color panelElevated;
  final Color workspace;
  final Color border;
  final Color muted;
  final Color sqlText;

  @override
  NodeQlWorkbenchColors copyWith({
    Color? topBar,
    Color? topBarForeground,
    Color? panel,
    Color? panelElevated,
    Color? workspace,
    Color? border,
    Color? muted,
    Color? sqlText,
  }) {
    return NodeQlWorkbenchColors(
      topBar: topBar ?? this.topBar,
      topBarForeground: topBarForeground ?? this.topBarForeground,
      panel: panel ?? this.panel,
      panelElevated: panelElevated ?? this.panelElevated,
      workspace: workspace ?? this.workspace,
      border: border ?? this.border,
      muted: muted ?? this.muted,
      sqlText: sqlText ?? this.sqlText,
    );
  }

  @override
  NodeQlWorkbenchColors lerp(covariant NodeQlWorkbenchColors? other, double t) {
    if (other == null) return this;
    return NodeQlWorkbenchColors(
      topBar: Color.lerp(topBar, other.topBar, t)!,
      topBarForeground: Color.lerp(
        topBarForeground,
        other.topBarForeground,
        t,
      )!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelElevated: Color.lerp(panelElevated, other.panelElevated, t)!,
      workspace: Color.lerp(workspace, other.workspace, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      sqlText: Color.lerp(sqlText, other.sqlText, t)!,
    );
  }
}
