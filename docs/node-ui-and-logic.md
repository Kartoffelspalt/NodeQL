# Node UI und Logik anpassen

Diese Notiz beschreibt, wo native NodeQL-Nodes ihr Aussehen, ihre Slots, ihre Andock-Regeln und ihre SQL-Logik bekommen.

## Überblick

Bei nativen Nodes sind UI und Logik auf mehrere Stellen verteilt:

- `lib/engine/block/block_node.dart`: Node-Typen, Serialisierung und Deserialisierung.
- `lib/engine/block/block_syntax.dart`: visuelle Rolle, Höhe, Connectoren und erlaubte SQL-Reihenfolge.
- `lib/features/workbench/presentation/engine/sql_labels.dart`: sichtbarer Node-Text, Simple Mode und Advanced Mode.
- `lib/features/workbench/presentation/workbench_page.dart`: Farben, Palette, Node-Rendering und Eingabe-UI.
- `lib/features/workbench/presentation/engine/sql_compiler.dart`: Übersetzung von Nodes zu SQL.

## 1. Node-Typ definieren

Alle nativen Node-Arten hängen am `BlockType` enum:

```dart
// lib/engine/block/block_node.dart
enum BlockType {
  sqlSelect,
  sqlWhere,
  sqlJoin,
  // ...
}
```

Wenn du einen neuen SQL-Node willst, kommt dort ein neuer Eintrag rein, zum Beispiel:

```dart
sqlLimit,
```

Danach muss `BlockNode.fromJson()` wissen, welche konkrete Node-Klasse daraus gebaut wird. Die meisten SQL-Nodes sind aktuell `OperatorBlock`. Container-Nodes verwenden `ControlBlock`, manche ältere Blöcke verwenden `MotionBlock`.

Für einen einfachen SQL-Node ist meistens richtig:

```dart
case BlockType.sqlLimit:
  node = OperatorBlock(
    id: json['id'] as String,
    position: offset,
    operatorType: type,
    inputs: inputs,
  );
```

## 2. Form, Höhe und Andock-Logik

Die visuelle Rolle eines Blocks wird in `block_syntax.dart` festgelegt.

Wichtige Rollen:

- `statement`: Haupt-SQL-Anweisung, zum Beispiel `SELECT`, `INSERT`, `UPDATE`.
- `clause`: SQL-Klausel, zum Beispiel `FROM`, `WHERE`, `GROUP BY`.
- `join`: Join-Blöcke.
- `expression`: Wert-/Reporter-Blöcke, zum Beispiel `COUNT`, `TEXT`, `COLUMN`.
- `container`: Blöcke mit Kind-Blöcken.
- `terminal`: Abschluss-Blöcke, zum Beispiel `COMMIT`, `ROLLBACK`.

Beispiel:

```dart
BlockType.sqlLimit => BlockVisualKind.clause,
```

Die Grundhöhe kommt aus:

```dart
double baseHeightForBlock(BlockNode node)
```

Die SQL-Reihenfolge beim Snappen wird hier gesteuert:

```dart
bool canFollowInSqlChain(BlockType previous, BlockType next)
```

Wenn `LIMIT` nach `ORDER BY` erlaubt sein soll, brauchst du dort eine Regel wie:

```dart
if (previous == BlockType.sqlOrderBy) {
  return next == BlockType.sqlLimit ||
      blockVisualKindForType(next) == BlockVisualKind.setOperator;
}
```

## 3. Text, Slots und Simple/Advanced Mode

Der sichtbare Text eines Nodes kommt aus `sql_labels.dart`.

Dort gibt es mehrere Maps:

- `adv`: technische SQL-Anzeige.
- `simpleDe`: deutsche Anfänger-Anzeige.
- `simpleEn`: englische Anfänger-Anzeige.
- `_simpleByLanguage()`: Sonderfälle für weitere Sprachen.

Beispiel:

```dart
BlockType.sqlLimit: 'LIMIT [count]',
```

Für Deutsch:

```dart
BlockType.sqlLimit: 'zeige nur [count] Zeilen',
```

Wichtig:

- Platzhalter in eckigen Klammern wie `[count]` werden als editierbare Inline-Inputs behandelt.
- Platzhalter in geschweiften Klammern wie `{value}` werden eher als Value-/Reporter-Slots verwendet.

Wenn du also möchtest, dass ein Node direkt im Block editierbare Felder hat, nutzt du passende Platzhalter im Label.

## 4. Farben und Rendering

Die Farben für native SQL-Nodes werden in `workbench_page.dart` bestimmt:

```dart
Color _sqlColorForType(BlockType type)
```

Dort wird anhand von `BlockVisualKind` oder konkretem `BlockType` eine Farbe aus `ScratchPalette` gewählt.

Beispiel:

```dart
BlockVisualKind.clause when type == BlockType.sqlWhere =>
  ScratchPalette.sqlFilter,
```

Das tatsächliche Rendering des Blocks passiert im Workspace ebenfalls in `workbench_page.dart`. Dort werden berechnet:

- Farbe
- Höhe
- Breite
- Template
- Inline-Slots
- Label-Maske
- `BlockShape`

Der zentrale Widget-Aufbau nutzt:

```dart
BlockShape(
  node: node,
  color: color,
  width: blockWidth,
  height: height,
  label: ...
)
```

Wenn du nur das Aussehen änderst, suchst du meistens in:

- `block_syntax.dart`
- `sql_labels.dart`
- `workbench_page.dart`
- `lib/features/workbench/presentation/widgets/block_shape_painter.dart`

## 5. Palette anpassen

Ob ein Node links in der Palette auftaucht, wird in `workbench_page.dart` in `_blocksForCategory()` gesteuert.

Beispiel:

```dart
SqlPaletteCategory.dql => <_PaletteItem>[
  native(BlockType.eventGreenFlag),
  native(BlockType.sqlSelect),
  native(BlockType.sqlWhere),
  native(BlockType.sqlLimit),
]
```

Wenn ein neuer Node nicht in der Palette steht, kann er nicht normal per UI hinzugefügt werden.

## 6. SQL-Logik anpassen

Die eigentliche Übersetzung von Nodes zu SQL liegt im `SqlCompiler`:

```dart
// lib/features/workbench/presentation/engine/sql_compiler.dart
String _compileSingle(BlockNode node, ...)
```

Dort gibt es pro `BlockType` einen `case`.

Beispiel für einen neuen `LIMIT`-Node:

```dart
case BlockType.sqlLimit:
  return 'LIMIT ${node.inputs['count'] as String? ?? '10'}';
```

Wenn du das Verhalten eines bestehenden Nodes ändern willst, änderst du den passenden `case`.

Beispiele:

- `sqlSelect`: Welche Spalten und welche Tabelle erzeugt werden.
- `sqlWhere`: Wie Bedingungen gebaut werden.
- `sqlJoin`: Wie Join-Type, Tabelle und `ON`-Bedingung erzeugt werden.
- `sqlGroupBy`: Wie Gruppierungen kompiliert werden.
- `sqlHaving`: Wie Aggregat-Bedingungen gebaut werden.

## 7. Beispiel: neuen LIMIT-Node hinzufügen

Minimaler Ablauf:

1. `BlockType.sqlLimit` in `block_node.dart` hinzufügen.
2. `sqlLimit` in `BlockNode.fromJson()` als `OperatorBlock` behandeln.
3. `sqlLimit` in `block_syntax.dart` als `BlockVisualKind.clause` einordnen.
4. `canFollowInSqlChain()` anpassen, damit `LIMIT` an der richtigen Stelle erlaubt ist.
5. Labels in `sql_labels.dart` ergänzen:

```dart
BlockType.sqlLimit: 'LIMIT [count]',
```

6. Den Node in `_blocksForCategory()` zur Palette hinzufügen.
7. Den Compiler in `sql_compiler.dart` ergänzen:

```dart
case BlockType.sqlLimit:
  return 'LIMIT ${node.inputs['count'] as String? ?? '10'}';
```

8. Tests ergänzen:

- Compiler-Test für erzeugtes SQL.
- Snap-/Syntax-Test für erlaubte Reihenfolge.
- Optional Widget-Test, wenn die UI des Blocks besonders ist.

## 8. Bestehenden Node ändern

Wenn du nur den Text ändern willst:

- `sql_labels.dart`

Wenn du Farbe oder Form ändern willst:

- `block_syntax.dart`
- `workbench_page.dart`
- eventuell `block_shape_painter.dart`

Wenn du ändern willst, wo der Node andocken darf:

- `block_syntax.dart`
- `workspace_engine.dart`, falls die Platzierungslogik selbst betroffen ist.

Wenn du ändern willst, welches SQL entsteht:

- `sql_compiler.dart`

Wenn du ändern willst, welche Felder der Node hat:

- `sql_labels.dart` für sichtbare Slots.
- `sql_compiler.dart` für die Nutzung der Inputs.
- eventuell Palette-Defaults in `workbench_page.dart`.

## 9. Tests

Nach Node-Änderungen solltest du mindestens ausführen:

```bash
flutter analyze
flutter test
```

Sinnvolle Testdateien:

- `test/runtime/sql_compiler_query_chain_test.dart`
- `test/workspace/block_syntax_test.dart`
- `test/workspace/workspace_engine_test.dart`
- `test/workspace/block_shape_widget_test.dart`

Wenn du neue Inputs oder Serialisierung änderst, prüfe zusätzlich die Serialization-Tests.

## Kurzregel

Für einen nativen Node brauchst du fast immer:

```text
BlockType -> Syntax/Form -> Label/Slots -> Palette -> Compiler -> Tests
```

Für reine UI-Anpassungen reichen oft:

```text
sql_labels.dart -> block_syntax.dart -> workbench_page.dart
```

Für echtes Verhalten brauchst du fast immer:

```text
sql_compiler.dart
```
