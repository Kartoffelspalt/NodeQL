# NodeQL: Change Playbooks for AI Agents

This document makes typical changes traceable and testable. It does not replace
the tests: existing tests and the actual implementation take precedence.

## Before every change

```bash
git status --short
rg -n "Suchbegriff" lib test docs
```

Work in the smallest suitable area. Do not manually edit generated files under
`lib/localization/generated/`, and do not touch unrelated existing worktree
changes.

## 1. Change visible text

There are two text systems:

| Text type | Source | Then |
| --- | --- | --- |
| Flutter UI and Material-adjacent text | `lib/l10n/app_*.arb` | `flutter gen-l10n` and relevant widget/localization tests |
| Community translation runtime catalogs | `translations/*.json`, `assets/translations/en.json` | `dart run tool/validate_translations.dart` |
| Block labels and simple/advanced mode | `lib/features/workbench/presentation/engine/sql_labels.dart` | block/widget tests; no ARB generation for this file alone |

Before adding text, find the existing call and its source. A new hard-coded
user-facing string in `workbench_page.dart` is almost always the wrong choice.

## 2. Add or change a native SQL block

Cover every affected layer:

1. `BlockType` and JSON construction in `lib/engine/block/block_node.dart`.
2. Visual role and allowed ordering in
   `lib/engine/block/block_syntax.dart`.
3. Dragging/docking behavior in
   `lib/features/workbench/presentation/engine/workspace_engine.dart`, if
   the standard behavior is not sufficient.
4. Palette, color, or special rendering in `workbench_page.dart`.
5. Labels, slots, and simple/advanced display in `sql_labels.dart`.
6. SQL compilation in `sql_compiler.dart`.
7. Update serialization, syntax/snap, and compiler tests.

At minimum, run:

```bash
flutter test test/serialization/block_node_serialization_test.dart
flutter test test/workspace/block_syntax_test.dart
flutter test test/workspace/workspace_docking_service_test.dart
flutter test test/runtime/sql_compiler_query_chain_test.dart
```

Details and an example `LIMIT` block are in
[`docs/node-ui-and-logic.md`](../node-ui-and-logic.md).

## 3. Change the SQLite runtime

The current runtime entry point is
`lib/features/workbench/presentation/engine/sql_runtime.dart`. NodeQL uses the
Dart `sqlite3` package, not `/usr/bin/sqlite3`.

Preserve these properties:

- Database selection and local file paths work across platforms.
- Schema reading excludes SQLite system tables.
- Multiple statements and container blocks are handled correctly.
- Write operations remain protected by snapshot and restoration.
- Errors remain useful without exposing platform-specific internals.

Verification:

```bash
flutter test test/runtime/sql_runtime_test.dart
flutter test test/runtime/sql_compiler_query_chain_test.dart
```

## 4. Change the Plugin SDK, manifest, or repository

Affected files are in `lib/engine/plugins/`; the contract is defined in
`docs/plugins/README.md` and the JSON schemas under `docs/plugins/`.

For a format or validation change, always check together:

- Parsing and validation in `plugin_manifest.dart`.
- Download, HTTPS, and hash checks in `plugin_repository.dart`.
- Palette/installation in `plugin_loader.dart` and `plugin_registry.dart`.
- Examples, schemas, and documentation.
- Persistent compatibility of plugin ID, block ID, and version.

```bash
flutter test test/plugins/plugin_manifest_test.dart
flutter test test/plugins/plugin_repository_test.dart
flutter test test/plugins/plugin_data_source_client_test.dart
```

The `sha256` in a repository catalog applies to the exact referenced
`plugin.json`, not a folder. For a 404, first check the resolved `manifestUrl`,
including capitalization.

## 5. Change the project format or autosave

Project files are long-lived user data. Entry points:

- `lib/domain/models/project_models.dart`
- `lib/data/persistence/json_project_repository.dart`
- `lib/data/project/project_file_upgrade_service.dart`
- `lib/features/workbench/presentation/workbench_page.dart`

Rules:

- Older supported files must remain readable.
- The existing service creates a backup before an upgrade; do not bypass it.
- Files from a newer NodeQL version must not be overwritten.

```bash
flutter test test/project/project_file_upgrade_service_test.dart
flutter test test/serialization/block_node_serialization_test.dart
```

## 6. Fix a UI, layout, or interaction defect

The workbench is large; first search for the exact visible text, widget, or
provider. For node rendering, the cause and display are often distributed
between `workbench_page.dart`, `block_syntax.dart`, `sql_labels.dart`, and
`widgets/block_shape_painter.dart`.

If a defect affects multiple node types or languages, fix it in shared
rendering or slot logic instead of adding one-off exceptions. Add a widget or
workspace test when the behavior can be expressed without manual testing.

```bash
flutter test test/workspace/block_shape_widget_test.dart
flutter test test/widget_test.dart
```

## Final check

For Dart changes, at least format and run affected tests. Before handoff,
preferably run:

```bash
dart format lib test tool
flutter analyze --no-pub
flutter test
```

After ARB changes, also run:

```bash
flutter gen-l10n
dart run tool/validate_translations.dart
```

If a check cannot run because of the local environment, report its result and
cause precisely rather than claiming it passed.
