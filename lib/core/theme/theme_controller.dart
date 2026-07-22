import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum NodeQlTheme { light, dark, midnight, matrix }

@immutable
class NodeQlThemeSettings {
  const NodeQlThemeSettings({required this.theme, this.accentColor});

  final NodeQlTheme theme;
  final Color? accentColor;

  NodeQlThemeSettings copyWith({
    NodeQlTheme? theme,
    Color? accentColor,
    bool clearAccent = false,
  }) {
    return NodeQlThemeSettings(
      theme: theme ?? this.theme,
      accentColor: clearAccent ? null : accentColor ?? this.accentColor,
    );
  }
}

/// Shared visual primitives for the desktop workbench.
///
/// Keeping these values in one place makes spacing, radii and motion feel
/// intentional across the application without coupling UI code to a theme.
abstract final class NodeQlDesign {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;

  static const double radiusSmall = 10;
  static const double radiusMedium = 14;
  static const double radiusLarge = 20;

  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
}

final nodeQlThemeProvider =
    StateNotifierProvider<NodeQlThemeController, NodeQlThemeSettings>(
      (_) => NodeQlThemeController(),
    );

class NodeQlThemeController extends StateNotifier<NodeQlThemeSettings> {
  NodeQlThemeController()
    : super(const NodeQlThemeSettings(theme: NodeQlTheme.dark)) {
    _restore();
  }

  Future<void> setTheme(NodeQlTheme theme) async {
    if (state.theme == theme) return;
    state = state.copyWith(theme: theme);
    await _persist();
  }

  Future<void> setAccentColor(Color color) async {
    if (state.accentColor?.toARGB32() == color.toARGB32()) return;
    state = state.copyWith(accentColor: color);
    await _persist();
  }

  Future<void> clearAccentColor() async {
    if (state.accentColor == null) return;
    state = state.copyWith(clearAccent: true);
    await _persist();
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
        final accentValue = decoded['accentColor'];
        final accent = accentValue is int ? Color(accentValue) : null;
        state = NodeQlThemeSettings(theme: matched.first, accentColor: accent);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final file = await _storageFile();
      final payload = <String, dynamic>{
        'theme': state.theme.name,
        if (state.accentColor != null)
          'accentColor': state.accentColor!.toARGB32(),
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

ThemeData themeFor(NodeQlTheme theme, {Color? accentColor}) {
  switch (theme) {
    case NodeQlTheme.light:
      return _buildTheme(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1D4ED8),
          secondary: Color(0xFF0369A1),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          outline: Color(0xFFCBD5E1),
        ),
        workbenchColors: NodeQlWorkbenchColors.light,
        accentColor: accentColor,
      );
    case NodeQlTheme.dark:
      return _buildTheme(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF22D3EE),
          surface: Color(0xFF0F172A),
          onSurface: Color(0xFFF8FAFC),
          outline: Color(0xFF334155),
        ),
        workbenchColors: NodeQlWorkbenchColors.dark,
        accentColor: accentColor,
      );
    case NodeQlTheme.midnight:
      return _buildTheme(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05121E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0A1A2A),
          onSurface: Color(0xFFF0F9FF),
          outline: Color(0xFF164E63),
        ),
        workbenchColors: NodeQlWorkbenchColors.midnight,
        accentColor: accentColor,
      );
    case NodeQlTheme.matrix:
      return _buildTheme(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040B05),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22C55E),
          secondary: Color(0xFF16A34A),
          surface: Color(0xFF07130A),
          onSurface: Color(0xFFD1FAE5),
          outline: Color(0xFF14532D),
        ),
        workbenchColors: NodeQlWorkbenchColors.matrix,
        accentColor: accentColor,
      );
  }
}

ColorScheme _withAccent(ColorScheme colorScheme, Color? accentColor) {
  if (accentColor == null) return colorScheme;
  final generated = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: colorScheme.brightness,
  );
  return colorScheme.copyWith(
    primary: generated.primary,
    onPrimary: generated.onPrimary,
    primaryContainer: generated.primaryContainer,
    onPrimaryContainer: generated.onPrimaryContainer,
    secondary: generated.secondary,
    onSecondary: generated.onSecondary,
    secondaryContainer: generated.secondaryContainer,
    onSecondaryContainer: generated.onSecondaryContainer,
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required Color scaffoldBackgroundColor,
  required ColorScheme colorScheme,
  required NodeQlWorkbenchColors workbenchColors,
  Color? accentColor,
}) {
  colorScheme = _withAccent(colorScheme, accentColor);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    visualDensity: VisualDensity.standard,
  );
  final onSurface = colorScheme.onSurface;
  final outline = colorScheme.outline;
  final roundedMedium = BorderRadius.circular(NodeQlDesign.radiusMedium);

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
          fontFamilyFallback: const [
            'Inter',
            'SF Pro Text',
            'Segoe UI',
            'Roboto',
          ],
        )
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
    dividerColor: outline.withValues(alpha: 0.72),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: workbenchColors.panelElevated,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NodeQlDesign.space3,
        vertical: NodeQlDesign.space3,
      ),
      border: OutlineInputBorder(
        borderRadius: roundedMedium,
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: roundedMedium,
        borderSide: BorderSide(color: outline.withValues(alpha: 0.82)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: roundedMedium,
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: workbenchColors.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: roundedMedium,
        side: BorderSide(color: outline.withValues(alpha: 0.7)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: workbenchColors.panelElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NodeQlDesign.radiusLarge),
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: workbenchColors.panelElevated,
      contentTextStyle: TextStyle(color: onSurface),
      shape: RoundedRectangleBorder(borderRadius: roundedMedium),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: NodeQlDesign.space4),
        shape: RoundedRectangleBorder(borderRadius: roundedMedium),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: NodeQlDesign.space4),
        shape: RoundedRectangleBorder(borderRadius: roundedMedium),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: roundedMedium),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: workbenchColors.panelElevated,
        borderRadius: BorderRadius.circular(NodeQlDesign.radiusSmall),
        border: Border.all(color: outline),
      ),
      textStyle: TextStyle(color: onSurface),
    ),
    extensions: <ThemeExtension<dynamic>>[workbenchColors],
  );
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
