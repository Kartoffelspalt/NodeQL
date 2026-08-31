import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum NodeQlTheme { light, dark, midnight, matrix, neoBrutalism }

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

  static const double radiusLarge = 20;
  static const double radiusLargeToMediumGap = 6;
  static const double radiusMedium = radiusLarge - radiusLargeToMediumGap;
  static const double radiusMediumToSmallGap = 4;
  static const double radiusSmall = radiusMedium - radiusMediumToSmallGap;

  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
}

/// Canonical Neo-Brutalism colors. Keep these deliberately small and loud:
/// paper neutrals provide reading comfort while three saturated accents carry
/// hierarchy and interaction feedback.
abstract final class NodeQlNeoBrutalism {
  static const Color ink = Color(0xFF1A1A1A);
  static const Color cream = Color(0xFFFFF4D8);
  static const Color paper = Color(0xFFFFFDF5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color violet = Color(0xFF5B5BF7);
  static const Color pink = Color(0xFFFF4D8D);
  static const Color yellow = Color(0xFFFFDE59);
  static const Color cyan = Color(0xFFBDE7FF);
  static const Color mint = Color(0xFFA7F3D0);
  static const Color mutedInk = Color(0xFF555555);

  static const double borderWidth = 2.5;
  static const Offset shadowOffset = Offset(4, 4);
  static const Duration interactionDuration = Duration(milliseconds: 90);
}

/// Theme-aware geometry and shadow tokens for custom workbench surfaces.
///
/// Material component themes cover controls, while NodeQL's canvas, palette,
/// and output panels are custom widgets. Keeping their styling here lets those
/// surfaces transition with the selected theme as one coherent system.
@immutable
class NodeQlSurfaceStyle extends ThemeExtension<NodeQlSurfaceStyle> {
  const NodeQlSurfaceStyle({
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.borderWidth,
    required this.shadowOffset,
    required this.shadowOpacity,
  });

  static const standard = NodeQlSurfaceStyle(
    radiusSmall: NodeQlDesign.radiusSmall,
    radiusMedium: NodeQlDesign.radiusMedium,
    radiusLarge: NodeQlDesign.radiusLarge,
    borderWidth: 1,
    shadowOffset: Offset.zero,
    shadowOpacity: 0,
  );

  static const neoBrutalism = NodeQlSurfaceStyle(
    radiusSmall: 2,
    radiusMedium: 4,
    radiusLarge: 6,
    borderWidth: NodeQlNeoBrutalism.borderWidth,
    shadowOffset: NodeQlNeoBrutalism.shadowOffset,
    shadowOpacity: 1,
  );

  static NodeQlSurfaceStyle of(BuildContext context) {
    return Theme.of(context).extension<NodeQlSurfaceStyle>() ?? standard;
  }

  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double borderWidth;
  final Offset shadowOffset;
  final double shadowOpacity;

  bool get isBrutalist => borderWidth > 1.5;

  BorderRadius get smallBorderRadius => BorderRadius.circular(radiusSmall);
  BorderRadius get mediumBorderRadius => BorderRadius.circular(radiusMedium);
  BorderRadius get largeBorderRadius => BorderRadius.circular(radiusLarge);

  /// Returns the concentric inner radius for a surface inset by [gap].
  ///
  /// Keeping this calculation here makes the geometry rule consistent across
  /// the app: outer corner radius minus the actual space to the inner surface.
  double innerRadius({required double outerRadius, required double gap}) =>
      (outerRadius - gap).clamp(0.0, double.infinity).toDouble();

  BorderRadius innerBorderRadius({
    required double outerRadius,
    required double gap,
  }) => BorderRadius.circular(innerRadius(outerRadius: outerRadius, gap: gap));

  BorderSide borderSide(Color color, {bool disabled = false}) => BorderSide(
    color: disabled ? color.withValues(alpha: 0.38) : color,
    width: borderWidth,
  );

  List<BoxShadow> get hardShadow => hardShadowFor();

  List<BoxShadow> hardShadowFor({
    bool hovered = false,
    bool pressed = false,
    bool disabled = false,
  }) {
    if (shadowOpacity == 0 || disabled) return const [];
    final offset = pressed
        ? const Offset(1, 1)
        : hovered
        ? shadowOffset + const Offset(1, 1)
        : shadowOffset;
    return [
      BoxShadow(
        color: NodeQlNeoBrutalism.ink.withValues(alpha: shadowOpacity),
        offset: offset,
        blurRadius: 0,
      ),
    ];
  }

  Offset translationFor({bool hovered = false, bool pressed = false}) {
    if (!isBrutalist) return Offset.zero;
    if (pressed) return shadowOffset - const Offset(1, 1);
    if (hovered) return const Offset(-1, -1);
    return Offset.zero;
  }

  BoxDecoration surfaceDecoration({
    required Color color,
    required Color borderColor,
    double? radius,
    bool elevated = true,
    bool disabled = false,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius ?? radiusMedium),
      border: Border.all(
        color: disabled ? borderColor.withValues(alpha: 0.38) : borderColor,
        width: borderWidth,
      ),
      boxShadow: elevated ? hardShadowFor(disabled: disabled) : null,
    );
  }

  @override
  NodeQlSurfaceStyle copyWith({
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? borderWidth,
    Offset? shadowOffset,
    double? shadowOpacity,
  }) {
    return NodeQlSurfaceStyle(
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      borderWidth: borderWidth ?? this.borderWidth,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
    );
  }

  @override
  NodeQlSurfaceStyle lerp(covariant NodeQlSurfaceStyle? other, double t) {
    if (other == null) return this;
    double lerpValue(double from, double to) => from + (to - from) * t;
    return NodeQlSurfaceStyle(
      radiusSmall: lerpValue(radiusSmall, other.radiusSmall),
      radiusMedium: lerpValue(radiusMedium, other.radiusMedium),
      radiusLarge: lerpValue(radiusLarge, other.radiusLarge),
      borderWidth: lerpValue(borderWidth, other.borderWidth),
      shadowOffset: Offset.lerp(shadowOffset, other.shadowOffset, t)!,
      shadowOpacity: lerpValue(shadowOpacity, other.shadowOpacity),
    );
  }
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
    case NodeQlTheme.neoBrutalism:
      return _buildTheme(
        brightness: Brightness.light,
        scaffoldBackgroundColor: NodeQlNeoBrutalism.cream,
        colorScheme: const ColorScheme.light(
          primary: NodeQlNeoBrutalism.violet,
          onPrimary: NodeQlNeoBrutalism.white,
          secondary: NodeQlNeoBrutalism.pink,
          onSecondary: NodeQlNeoBrutalism.ink,
          tertiary: NodeQlNeoBrutalism.yellow,
          onTertiary: NodeQlNeoBrutalism.ink,
          surface: NodeQlNeoBrutalism.paper,
          onSurface: NodeQlNeoBrutalism.ink,
          surfaceContainerHighest: NodeQlNeoBrutalism.mint,
          onSurfaceVariant: NodeQlNeoBrutalism.mutedInk,
          error: Color(0xFFE63946),
          onError: NodeQlNeoBrutalism.white,
          outline: NodeQlNeoBrutalism.ink,
        ),
        workbenchColors: NodeQlWorkbenchColors.neoBrutalism,
        accentColor: accentColor,
        neoBrutalist: true,
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
  bool neoBrutalist = false,
}) {
  colorScheme = _withAccent(colorScheme, accentColor);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    visualDensity: VisualDensity.standard,
    splashFactory: neoBrutalist ? NoSplash.splashFactory : null,
  );
  final onSurface = colorScheme.onSurface;
  final outline = colorScheme.outline;
  final surfaceStyle = neoBrutalist
      ? NodeQlSurfaceStyle.neoBrutalism
      : NodeQlSurfaceStyle.standard;
  final roundedMedium = surfaceStyle.mediumBorderRadius;
  final roundedLarge = surfaceStyle.largeBorderRadius;
  final borderSide = surfaceStyle.borderSide(outline);
  final disabledBorderSide = surfaceStyle.borderSide(outline, disabled: true);
  final brutalButtonSide = WidgetStateProperty.resolveWith<BorderSide?>((
    states,
  ) {
    return states.contains(WidgetState.disabled)
        ? disabledBorderSide
        : borderSide;
  });
  final brutalButtonElevation = WidgetStateProperty.resolveWith<double?>((
    states,
  ) {
    if (states.contains(WidgetState.disabled) ||
        states.contains(WidgetState.pressed)) {
      return 0;
    }
    return states.contains(WidgetState.hovered) ? 1 : 0;
  });
  final brutalButtonOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.disabled)) return Colors.transparent;
    if (states.contains(WidgetState.pressed)) {
      return NodeQlNeoBrutalism.ink.withValues(alpha: 0.18);
    }
    if (states.contains(WidgetState.hovered)) {
      return NodeQlNeoBrutalism.white.withValues(alpha: 0.18);
    }
    if (states.contains(WidgetState.focused)) {
      return colorScheme.tertiary.withValues(alpha: 0.3);
    }
    return Colors.transparent;
  });
  final brutalButtonForeground = WidgetStateProperty.resolveWith<Color?>((
    states,
  ) {
    return states.contains(WidgetState.disabled)
        ? onSurface.withValues(alpha: 0.42)
        : null;
  });
  // Keep the same concrete shape type in every theme. In particular, this
  // lets Flutter interpolate the corners cleanly when leaving Neo Brutalism
  // instead of falling back to a component-specific default shape.
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: roundedMedium),
  );
  final brutalButtonPadding = const WidgetStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.symmetric(
      horizontal: NodeQlDesign.space4,
      vertical: NodeQlDesign.space3,
    ),
  );
  final brutalButtonMinimumSize = const WidgetStatePropertyAll<Size>(
    Size(44, 44),
  );
  final textTheme = base.textTheme
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
          fontWeight: neoBrutalist ? FontWeight.w900 : FontWeight.w700,
          letterSpacing: neoBrutalist ? 0.2 : -0.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: neoBrutalist ? FontWeight.w900 : FontWeight.w700,
          letterSpacing: neoBrutalist ? 0.15 : -0.1,
        ),
        titleSmall: neoBrutalist
            ? base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
            : null,
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          fontWeight: neoBrutalist ? FontWeight.w500 : null,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: neoBrutalist ? FontWeight.w900 : FontWeight.w700,
          letterSpacing: neoBrutalist ? 0.35 : 0.1,
        ),
      );

  return base.copyWith(
    textTheme: textTheme,
    focusColor: neoBrutalist
        ? colorScheme.tertiary.withValues(alpha: 0.28)
        : null,
    hoverColor: neoBrutalist
        ? colorScheme.primary.withValues(alpha: 0.08)
        : null,
    highlightColor: neoBrutalist
        ? NodeQlNeoBrutalism.ink.withValues(alpha: 0.08)
        : null,
    textSelectionTheme: neoBrutalist
        ? TextSelectionThemeData(
            cursorColor: colorScheme.primary,
            selectionColor: colorScheme.tertiary.withValues(alpha: 0.72),
            selectionHandleColor: outline,
          )
        : null,
    dividerColor: neoBrutalist ? outline : outline.withValues(alpha: 0.72),
    dividerTheme: neoBrutalist
        ? DividerThemeData(color: outline, thickness: 2.5, space: 24)
        : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: workbenchColors.panelElevated,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NodeQlDesign.space3,
        vertical: NodeQlDesign.space3,
      ),
      hoverColor: neoBrutalist
          ? colorScheme.tertiary.withValues(alpha: 0.16)
          : null,
      border: OutlineInputBorder(
        borderRadius: roundedMedium,
        borderSide: borderSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: roundedMedium,
        borderSide: neoBrutalist
            ? borderSide
            : BorderSide(color: outline.withValues(alpha: 0.82)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: roundedMedium,
        borderSide: BorderSide(
          color: neoBrutalist ? outline : colorScheme.primary,
          width: neoBrutalist ? 3.5 : 2,
        ),
      ),
      disabledBorder: neoBrutalist
          ? OutlineInputBorder(
              borderRadius: roundedMedium,
              borderSide: disabledBorderSide,
            )
          : null,
      errorBorder: neoBrutalist
          ? OutlineInputBorder(
              borderRadius: roundedMedium,
              borderSide: BorderSide(
                color: colorScheme.error,
                width: surfaceStyle.borderWidth,
              ),
            )
          : null,
      focusedErrorBorder: neoBrutalist
          ? OutlineInputBorder(
              borderRadius: roundedMedium,
              borderSide: BorderSide(color: colorScheme.error, width: 3.5),
            )
          : null,
      errorStyle: neoBrutalist
          ? textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w800,
            )
          : null,
      prefixIconColor: neoBrutalist
          ? WidgetStateColor.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return onSurface.withValues(alpha: 0.38);
              }
              if (states.contains(WidgetState.focused)) {
                return colorScheme.primary;
              }
              return onSurface;
            })
          : null,
      suffixIconColor: neoBrutalist
          ? WidgetStateColor.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return onSurface.withValues(alpha: 0.38);
              }
              return onSurface;
            })
          : null,
    ),
    cardTheme: CardThemeData(
      color: workbenchColors.panel,
      elevation: 0,
      shadowColor: neoBrutalist ? outline : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: roundedMedium,
        side: neoBrutalist
            ? borderSide
            : BorderSide(color: outline.withValues(alpha: 0.7)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: workbenchColors.panelElevated,
      elevation: neoBrutalist ? 10 : null,
      shadowColor: neoBrutalist ? outline : null,
      surfaceTintColor: Colors.transparent,
      clipBehavior: neoBrutalist ? Clip.none : Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: roundedLarge,
        side: neoBrutalist ? borderSide : BorderSide.none,
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: onSurface,
        fontWeight: neoBrutalist ? FontWeight.w900 : FontWeight.w700,
      ),
      actionsPadding: neoBrutalist
          ? const EdgeInsets.fromLTRB(24, 8, 24, 20)
          : null,
      insetPadding: neoBrutalist
          ? const EdgeInsets.symmetric(horizontal: 32, vertical: 24)
          : null,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: neoBrutalist
          ? colorScheme.tertiary
          : workbenchColors.panelElevated,
      contentTextStyle: TextStyle(color: onSurface),
      elevation: neoBrutalist ? 8 : null,
      shape: RoundedRectangleBorder(
        borderRadius: roundedMedium,
        side: neoBrutalist ? borderSide : BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: neoBrutalist
          ? ButtonStyle(
              minimumSize: brutalButtonMinimumSize,
              padding: brutalButtonPadding,
              elevation: brutalButtonElevation,
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              foregroundColor: brutalButtonForeground,
              overlayColor: brutalButtonOverlay,
              side: brutalButtonSide,
              shape: buttonShape,
              animationDuration: NodeQlNeoBrutalism.interactionDuration,
            )
          : FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(
                horizontal: NodeQlDesign.space4,
              ),
              shape: RoundedRectangleBorder(borderRadius: roundedMedium),
            ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: neoBrutalist
          ? ButtonStyle(
              minimumSize: brutalButtonMinimumSize,
              padding: brutalButtonPadding,
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? workbenchColors.panel.withValues(alpha: 0.62)
                    : workbenchColors.panelElevated;
              }),
              foregroundColor: brutalButtonForeground,
              elevation: brutalButtonElevation,
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.tertiary.withValues(alpha: 0.72);
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.tertiary.withValues(alpha: 0.38);
                }
                if (states.contains(WidgetState.focused)) {
                  return colorScheme.primary.withValues(alpha: 0.16);
                }
                return Colors.transparent;
              }),
              side: brutalButtonSide,
              shape: buttonShape,
              animationDuration: NodeQlNeoBrutalism.interactionDuration,
            )
          : OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(
                horizontal: NodeQlDesign.space4,
              ),
              shape: RoundedRectangleBorder(borderRadius: roundedMedium),
            ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: neoBrutalist
          ? ButtonStyle(
              minimumSize: brutalButtonMinimumSize,
              padding: brutalButtonPadding,
              elevation: brutalButtonElevation,
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              foregroundColor: brutalButtonForeground,
              overlayColor: brutalButtonOverlay,
              side: brutalButtonSide,
              shape: buttonShape,
              animationDuration: NodeQlNeoBrutalism.interactionDuration,
            )
          : ButtonStyle(shape: buttonShape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: neoBrutalist
          ? ButtonStyle(
              minimumSize: brutalButtonMinimumSize,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: NodeQlDesign.space3,
                  vertical: NodeQlDesign.space2,
                ),
              ),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? onSurface.withValues(alpha: 0.38)
                    : colorScheme.primary;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.tertiary.withValues(alpha: 0.82);
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.tertiary.withValues(alpha: 0.42);
                }
                return Colors.transparent;
              }),
              shape: buttonShape,
              animationDuration: NodeQlNeoBrutalism.interactionDuration,
            )
          : ButtonStyle(shape: buttonShape),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: neoBrutalist
          ? ButtonStyle(
              minimumSize: brutalButtonMinimumSize,
              foregroundColor: brutalButtonForeground,
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return workbenchColors.panel.withValues(alpha: 0.45);
                }
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.tertiary;
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.tertiary.withValues(alpha: 0.62);
                }
                return workbenchColors.panelElevated;
              }),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              side: brutalButtonSide,
              shape: buttonShape,
              animationDuration: NodeQlNeoBrutalism.interactionDuration,
            )
          : IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(borderRadius: roundedMedium),
            ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: neoBrutalist
          ? ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return workbenchColors.panel.withValues(alpha: 0.6);
                }
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.secondary.withValues(alpha: 0.72);
                }
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.tertiary;
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.tertiary.withValues(alpha: 0.42);
                }
                return workbenchColors.panelElevated;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? onSurface.withValues(alpha: 0.38)
                    : onSurface;
              }),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              side: brutalButtonSide,
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: roundedMedium),
              ),
              animationDuration: NodeQlNeoBrutalism.interactionDuration,
            )
          : ButtonStyle(shape: buttonShape),
    ),
    checkboxTheme: neoBrutalist
        ? CheckboxThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: surfaceStyle.smallBorderRadius,
            ),
            side: WidgetStateBorderSide.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? disabledBorderSide
                  : borderSide;
            }),
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return workbenchColors.panel;
              }
              return states.contains(WidgetState.selected)
                  ? colorScheme.primary
                  : workbenchColors.panelElevated;
            }),
            checkColor: const WidgetStatePropertyAll(NodeQlNeoBrutalism.white),
            overlayColor: WidgetStatePropertyAll(
              colorScheme.tertiary.withValues(alpha: 0.36),
            ),
          )
        : null,
    radioTheme: neoBrutalist
        ? RadioThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return onSurface.withValues(alpha: 0.38);
              }
              return states.contains(WidgetState.selected)
                  ? colorScheme.primary
                  : outline;
            }),
            overlayColor: WidgetStatePropertyAll(
              colorScheme.tertiary.withValues(alpha: 0.42),
            ),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          )
        : null,
    switchTheme: neoBrutalist
        ? SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return onSurface.withValues(alpha: 0.38);
              }
              return states.contains(WidgetState.selected)
                  ? NodeQlNeoBrutalism.ink
                  : workbenchColors.panelElevated;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return workbenchColors.panel;
              }
              return states.contains(WidgetState.selected)
                  ? colorScheme.tertiary
                  : workbenchColors.panelElevated;
            }),
            trackOutlineColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? outline.withValues(alpha: 0.38)
                  : outline;
            }),
            trackOutlineWidth: WidgetStatePropertyAll(surfaceStyle.borderWidth),
            overlayColor: WidgetStatePropertyAll(
              colorScheme.tertiary.withValues(alpha: 0.36),
            ),
          )
        : null,
    popupMenuTheme: neoBrutalist
        ? PopupMenuThemeData(
            color: workbenchColors.panelElevated,
            elevation: 8,
            shadowColor: outline,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: roundedMedium,
              side: borderSide,
            ),
          )
        : null,
    menuTheme: neoBrutalist
        ? MenuThemeData(
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(
                workbenchColors.panelElevated,
              ),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(0),
              side: WidgetStatePropertyAll(borderSide),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: roundedMedium),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: NodeQlDesign.space1),
              ),
            ),
          )
        : null,
    scrollbarTheme: neoBrutalist
        ? ScrollbarThemeData(
            thickness: const WidgetStatePropertyAll(12),
            radius: const Radius.circular(2),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.hovered)
                  ? colorScheme.primary
                  : outline;
            }),
            trackColor: WidgetStatePropertyAll(workbenchColors.panelElevated),
            trackBorderColor: WidgetStatePropertyAll(outline),
            crossAxisMargin: 2,
            mainAxisMargin: 2,
          )
        : null,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: workbenchColors.panelElevated,
        borderRadius: BorderRadius.circular(
          neoBrutalist ? 2 : NodeQlDesign.radiusSmall,
        ),
        border: Border.all(color: outline, width: neoBrutalist ? 2 : 1),
        boxShadow: neoBrutalist
            ? const [
                BoxShadow(
                  color: NodeQlNeoBrutalism.ink,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      textStyle: TextStyle(
        color: onSurface,
        fontWeight: neoBrutalist ? FontWeight.w800 : null,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[
      workbenchColors,
      neoBrutalist
          ? NodeQlSurfaceStyle.neoBrutalism
          : NodeQlSurfaceStyle.standard,
    ],
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

  static const neoBrutalism = NodeQlWorkbenchColors(
    topBar: NodeQlNeoBrutalism.yellow,
    topBarForeground: NodeQlNeoBrutalism.ink,
    panel: NodeQlNeoBrutalism.paper,
    panelElevated: NodeQlNeoBrutalism.white,
    workspace: NodeQlNeoBrutalism.cyan,
    border: NodeQlNeoBrutalism.ink,
    muted: NodeQlNeoBrutalism.mutedInk,
    sqlText: Color(0xFF29298F),
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
