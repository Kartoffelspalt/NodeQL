import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/core/theme/nodeql_brutal_pressable.dart';
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

  test('a custom accent is propagated through the Material color scheme', () {
    const accent = Color(0xFF7C3AED);
    final theme = themeFor(NodeQlTheme.dark, accentColor: accent);

    expect(theme.colorScheme.primary, isNot(const Color(0xFF3B82F6)));
    expect(theme.colorScheme.primary, isNot(theme.colorScheme.secondary));
    expect(theme.brightness, Brightness.dark);
  });

  test(
    'neo brutalism uses a bold light palette and heavy component borders',
    () {
      final theme = themeFor(NodeQlTheme.neoBrutalism);
      final colors = theme.extension<NodeQlWorkbenchColors>();
      final surfaces = theme.extension<NodeQlSurfaceStyle>();
      final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
      final buttonStyle = theme.filledButtonTheme.style!;

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, NodeQlNeoBrutalism.violet);
      expect(colors, NodeQlWorkbenchColors.neoBrutalism);
      expect(surfaces, NodeQlSurfaceStyle.neoBrutalism);
      expect(colors!.topBar, NodeQlNeoBrutalism.yellow);
      expect(surfaces!.shadowOffset, const Offset(4, 4));
      expect(cardShape.side.color, NodeQlNeoBrutalism.ink);
      expect(cardShape.side.width, 2.5);
      expect(buttonStyle.elevation!.resolve({}), 0);
      expect(buttonStyle.elevation!.resolve({WidgetState.hovered}), 1);
      expect(
        buttonStyle.side!.resolve({WidgetState.disabled})!.color.a,
        closeTo(0.38, 0.01),
      );
      expect(theme.textTheme.titleLarge!.fontWeight, FontWeight.w900);
    },
  );

  test(
    'neo brutal surface tokens provide crisp physical interaction states',
    () {
      const style = NodeQlSurfaceStyle.neoBrutalism;

      expect(style.hardShadow.single.blurRadius, 0);
      expect(style.hardShadow.single.offset, const Offset(4, 4));
      expect(
        style.hardShadowFor(hovered: true).single.offset,
        const Offset(5, 5),
      );
      expect(
        style.hardShadowFor(pressed: true).single.offset,
        const Offset(1, 1),
      );
      expect(style.translationFor(pressed: true), const Offset(3, 3));
      expect(style.hardShadowFor(disabled: true), isEmpty);
    },
  );

  testWidgets('switching to neo brutalism animates without theme exceptions', (
    tester,
  ) async {
    var selectedTheme = NodeQlTheme.dark;
    late StateSetter updateTheme;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateTheme = setState;
          return MaterialApp(
            theme: themeFor(selectedTheme),
            home: Scaffold(
              body: Column(
                children: [
                  RadioGroup<NodeQlTheme>(
                    groupValue: selectedTheme,
                    onChanged: (_) {},
                    child: const RadioListTile<NodeQlTheme>(
                      value: NodeQlTheme.neoBrutalism,
                      title: Text('Neo Brutalism'),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Mount database'),
                  ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Run query'),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Simple')),
                      ButtonSegment(value: true, label: Text('Advanced')),
                    ],
                    selected: const {false},
                    onSelectionChanged: (_) {},
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    updateTheme(() => selectedTheme = NodeQlTheme.neoBrutalism);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('brutal pressable lifts on hover and collapses on press', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(NodeQlTheme.neoBrutalism),
        home: const Scaffold(
          body: Center(
            child: NodeQlBrutalPressable(
              child: SizedBox(
                key: ValueKey('pressable-child'),
                width: 120,
                height: 44,
              ),
            ),
          ),
        ),
      ),
    );

    final child = find.byKey(const ValueKey('pressable-child'));
    final animated = find.descendant(
      of: find.byType(NodeQlBrutalPressable),
      matching: find.byType(AnimatedContainer),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(child));
    await tester.pumpAndSettle();

    var container = tester.widget<AnimatedContainer>(animated);
    var decoration = container.decoration! as BoxDecoration;
    expect(decoration.boxShadow!.single.offset, const Offset(5, 5));
    expect(container.transform!.storage[12], -1);
    expect(container.transform!.storage[13], -1);

    await mouse.down(tester.getCenter(child));
    await tester.pumpAndSettle();

    container = tester.widget<AnimatedContainer>(animated);
    decoration = container.decoration! as BoxDecoration;
    expect(decoration.boxShadow!.single.offset, const Offset(1, 1));
    expect(container.transform!.storage[12], 3);
    expect(container.transform!.storage[13], 3);

    await mouse.up();
    await mouse.removePointer();
  });
}
