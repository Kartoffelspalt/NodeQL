# Changing Node UI and Logic

This note explains where native NodeQL nodes get their appearance, slots,
docking rules, and SQL behavior.

## Overview

Native node UI and logic are distributed across several locations:

- `lib/engine/block/block_node.dart`: node types, serialization, and
  deserialization.
- `lib/engine/block/block_syntax.dart`: visual role, height, connectors, and
  permitted SQL ordering.
- `lib/features/workbench/presentation/engine/sql_labels.dart`: visible node
  text and simple/advanced mode.
- `lib/features/workbench/presentation/workbench_page.dart`: colors, palette,
  node rendering, and input UI.
- `lib/features/workbench/presentation/engine/sql_compiler.dart`: conversion of
  nodes to SQL.

## 1. Define a node type

All native node kinds belong to the `BlockType` enum:

```dart
// lib/engine/block/block_node.dart
enum BlockType {
  sqlSelect,
  sqlWhere,
  sqlJoin,
  // ...
}
```

To add a SQL node, add an entry such as:

```dart
sqlLimit,
```

Then teach `BlockNode.fromJson()` which concrete node class it creates. Most
current SQL nodes are `OperatorBlock`s. Container nodes use `ControlBlock`,
while some older blocks use `MotionBlock`.

For a simple SQL node, this is usually appropriate:

```dart
case BlockType.sqlLimit:
  node = OperatorBlock(
    id: json['id'] as String,
    position: offset,
    operatorType: type,
    inputs: inputs,
  );
```

## 2. Shape, height, and docking logic

`block_syntax.dart` defines a block's visual role.

Important roles:

- `statement`: primary SQL statements such as `SELECT`, `INSERT`, and `UPDATE`.
- `clause`: SQL clauses such as `FROM`, `WHERE`, and `GROUP BY`.
- `join`: join blocks.
- `expression`: value/reporter blocks such as `COUNT`, `TEXT`, and `COLUMN`.
- `container`: blocks with child blocks.
- `terminal`: ending blocks such as `COMMIT` and `ROLLBACK`.

Example:

```dart
BlockType.sqlLimit => BlockVisualKind.clause,
```

The base height comes from:

```dart
double baseHeightForBlock(BlockNode node)
```

The SQL ordering used while snapping is controlled here:

```dart
bool canFollowInSqlChain(BlockType previous, BlockType next)
```

To allow `LIMIT` after `ORDER BY`, add a rule such as:

```dart
if (previous == BlockType.sqlOrderBy) {
  return next == BlockType.sqlLimit ||
      blockVisualKindForType(next) == BlockVisualKind.setOperator;
}
```

## 3. Text, slots, and simple/advanced mode

Visible node text comes from `sql_labels.dart`.

It contains several maps:

- `adv`: technical SQL display.
- `simpleDe`: beginner-oriented German display.
- `simpleEn`: beginner-oriented English display.
- `_simpleByLanguage()`: special cases for other languages.

Example:

```dart
BlockType.sqlLimit: 'LIMIT [count]',
```

For a German simple label:

```dart
BlockType.sqlLimit: 'zeige nur [count] Zeilen',
```

Important details:

- Square-bracket placeholders such as `[count]` become editable inline inputs.
- Curly-brace placeholders such as `{value}` are normally value/reporter slots.

Use the appropriate placeholder when a node needs directly editable fields.

## 4. Colors and rendering

`workbench_page.dart` assigns colors to native SQL nodes:

```dart
Color _sqlColorForType(BlockType type)
```

It selects a `ScratchPalette` color from `BlockVisualKind` or a concrete
`BlockType`.

Example:

```dart
BlockVisualKind.clause when type == BlockType.sqlWhere =>
  ScratchPalette.sqlFilter,
```

The workbench also renders the actual block. It calculates the color, height,
width, template, inline slots, label mask, and `BlockShape`.

The central widget construction is:

```dart
BlockShape(
  node: node,
  color: color,
  width: blockWidth,
  height: height,
  label: ...,
)
```

For an appearance-only change, start with:

- `block_syntax.dart`
- `sql_labels.dart`
- `workbench_page.dart`
- `lib/features/workbench/presentation/widgets/block_shape_painter.dart`

## 5. Change the palette

`_blocksForCategory()` in `workbench_page.dart` controls whether a node appears
in the left palette.

Example:

```dart
SqlPaletteCategory.dql => <_PaletteItem>[
  native(BlockType.eventGreenFlag),
  native(BlockType.sqlSelect),
  native(BlockType.sqlWhere),
  native(BlockType.sqlLimit),
]
```

If a new node is not in the palette, users cannot normally add it through the
UI.

## 6. Change SQL behavior

`SqlCompiler` contains the actual translation from nodes to SQL:

```dart
// lib/features/workbench/presentation/engine/sql_compiler.dart
String _compileSingle(BlockNode node, ...)
```

It has a `case` for each `BlockType`.

Example for a new `LIMIT` node:

```dart
case BlockType.sqlLimit:
  return 'LIMIT ${node.inputs['count'] as String? ?? '10'}';
```

To change an existing node's behavior, update its corresponding `case`.

Examples:

- `sqlSelect`: columns and table generation.
- `sqlWhere`: condition construction.
- `sqlJoin`: join type, table, and `ON` condition construction.
- `sqlGroupBy`: grouping construction.
- `sqlHaving`: aggregate condition construction.

## 7. Example: add a LIMIT node

Minimal sequence:

1. Add `BlockType.sqlLimit` to `block_node.dart`.
2. Handle `sqlLimit` as an `OperatorBlock` in `BlockNode.fromJson()`.
3. Classify `sqlLimit` as `BlockVisualKind.clause` in `block_syntax.dart`.
4. Update `canFollowInSqlChain()` so `LIMIT` is allowed at the correct point.
5. Add labels in `sql_labels.dart`:

   ```dart
   BlockType.sqlLimit: 'LIMIT [count]',
   ```

6. Add the node to the palette in `_blocksForCategory()`.
7. Add the compiler case in `sql_compiler.dart`:

   ```dart
   case BlockType.sqlLimit:
     return 'LIMIT ${node.inputs['count'] as String? ?? '10'}';
   ```

8. Add tests:

   - compiler test for generated SQL;
   - snap/syntax test for permitted ordering;
   - widget test when the node UI is special.

## 8. Change an existing node

To change only text:

- `sql_labels.dart`

To change color or shape:

- `block_syntax.dart`
- `workbench_page.dart`
- optionally `block_shape_painter.dart`

To change allowed docking locations:

- `block_syntax.dart`
- `workspace_engine.dart` when placement logic itself is affected.

To change generated SQL:

- `sql_compiler.dart`

To change a node's fields:

- `sql_labels.dart` for visible slots;
- `sql_compiler.dart` for input usage;
- optionally palette defaults in `workbench_page.dart`.

## 9. Tests

After node changes, run at least:

```bash
flutter analyze
flutter test
```

Useful test files:

- `test/runtime/sql_compiler_query_chain_test.dart`
- `test/workspace/block_syntax_test.dart`
- `test/workspace/workspace_engine_test.dart`
- `test/workspace/block_shape_widget_test.dart`

When adding inputs or changing serialization, also check serialization tests.

## Short rule

For a native node, you almost always need:

```text
BlockType -> syntax/shape -> labels/slots -> palette -> compiler -> tests
```

For a UI-only adjustment, these are often sufficient:

```text
sql_labels.dart -> block_syntax.dart -> workbench_page.dart
```

For behavior, you almost always need:

```text
sql_compiler.dart
```
