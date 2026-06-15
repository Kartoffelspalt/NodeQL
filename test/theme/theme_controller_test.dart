import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/theme/theme_controller.dart';

void main() {
  test('white mode provides a complete light workbench palette', () {
    final theme = themeFor(NodeQlTheme.light);
    final colors = theme.extension<NodeQlWorkbenchColors>();

    expect(theme.brightness, Brightness.light);
    expect(colors, isNotNull);
    expect(colors!.workspace, isNot(const Color(0xFF111827)));
    expect(
      ThemeData.estimateBrightnessForColor(colors.workspace),
      Brightness.light,
    );
    expect(
      ThemeData.estimateBrightnessForColor(colors.topBar),
      Brightness.light,
    );
  });

  test('all dark variants keep dark workbench surfaces', () {
    for (final variant in const [
      NodeQlTheme.dark,
      NodeQlTheme.midnight,
      NodeQlTheme.matrix,
    ]) {
      final theme = themeFor(variant);
      final colors = theme.extension<NodeQlWorkbenchColors>();

      expect(theme.brightness, Brightness.dark);
      expect(colors, isNotNull);
      expect(
        ThemeData.estimateBrightnessForColor(colors!.workspace),
        Brightness.dark,
      );
    }
  });
}
