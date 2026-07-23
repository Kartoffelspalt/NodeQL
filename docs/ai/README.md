# NodeQL: AI Agent Guide

This document is the entry point for AI agents working on NodeQL. It describes
the current code structure and links to the [change playbooks](change-playbooks.md)
for recurring work. It complements `AGENTS.md`; when instructions conflict,
the repository instructions in `AGENTS.md` take precedence.

## 1. Project in one sentence

NodeQL is a local Flutter desktop application where users build SQL with visual
blocks, inspect the generated SQL, and execute it against local SQLite databases.

Important product boundaries:

- No cloud backend, account, analytics, or machine-learning pipeline.
- SQLite files, projects, settings, and installed plugins remain local.
- Plugins are declarative JSON manifests; NodeQL does not load third-party
  Dart, native, or script code.
- According to `README.md`, the project is a **public preview**. Do not make a
  stronger release claim without checking `README.md` and `docs/RELEASING.md`.

## 2. Entry point and data flow

```text
lib/main.dart
  -> ProviderScope
  -> NodeQlApp (theme and language)
  -> WorkbenchShell
  -> WorkbenchPage

Block-Palette / Drag-and-drop
  -> WorkspaceController
  -> BlockNode tree (roots, next, children)
  -> SqlCompiler
  -> SqlRuntime (sqlite3)
  -> result and status display
```

Only chains below `BlockType.eventGreenFlag` (`EXECUTE QUERY`) compile as SQL.
Floating blocks are deliberately not executable.

## 3. Source map

| Area | Responsibility | First places to inspect |
| --- | --- | --- |
| App shell | Flutter startup, theme, locale, shell | `lib/main.dart`, `lib/core/app/nodeql_app.dart`, `lib/ui/shell/workbench_shell.dart` |
| Workbench | visible UI and dialogs | `lib/features/workbench/presentation/workbench_page.dart` |
| Workbench state | blocks, selection, undo/redo, dragging, serialization | `lib/features/workbench/presentation/engine/workspace_engine.dart` |
| Block model | types, nodes, JSON, syntax, docking | `lib/engine/block/`, `lib/engine/workspace/workspace_docking_service.dart` |
| SQL | labels, abstraction mode, compilation, SQLite access | `lib/features/workbench/presentation/engine/sql_*.dart` |
| Projects | project data, JSON persistence, upgrades, default project | `lib/domain/models/`, `lib/data/project/`, `lib/data/persistence/` |
| Plugins | manifests, validation, repositories, data sources | `lib/engine/plugins/`, `docs/plugins/README.md` |
| Language | ARB UI text and installable translations | `lib/l10n/`, `lib/localization/`, `translations/` |
| Tests | subsystem-level unit and widget tests | `test/` |

Most visible workbench changes begin in `workbench_page.dart`, but logic should
not be moved there. New state or interaction logic normally belongs in the
appropriate controller or engine file.

## 4. Core block contract

A native block commonly affects more than one file:

```text
BlockType / JSON      lib/engine/block/block_node.dart
Syntax and ordering    lib/engine/block/block_syntax.dart
Workspace behavior     .../engine/workspace_engine.dart
Palette and rendering  workbench_page.dart
Labels and slots       .../engine/sql_labels.dart
SQL output             .../engine/sql_compiler.dart
Tests                  test/runtime and test/workspace
```

`next` represents the following clause in a chain; `children` represents
embedded or nested blocks. Connection behavior is part of the data model, so a
UI-only change must not bypass it inadvertently.

For a detailed sequence, see [node UI and logic](../node-ui-and-logic.md).

## 5. State and dependencies

The app uses Riverpod. Important providers are:

- `workspaceProvider`: visual block workspace and editing.
- `sqlRuntimeProvider`: database, schema, execution, and results.
- `pluginPaletteProvider`: installed plugins and plugin palette.
- `translationControllerProvider`: active locale and runtime catalogs.
- `nodeQlThemeProvider`: theme.

When changing a provider, first locate its reads and writes with
`rg "providerName" lib test`. Apply changes through the controller rather than
mutating state objects from widgets.

## 6. Non-negotiable boundaries

- Existing project and block JSON structures are persistent. New fields need
  safe defaults, and older files must remain readable.
- Plugin IDs and block IDs are persistent. Never reuse one for different
  behavior.
- Plugin and translation downloads are security boundaries: do not weaken
  HTTPS, schema, size, or hash checks.
- SQL statements can change data. Preserve the existing snapshot/restore flow
  and error paths in runtime code.
- All visible text is localizable. Do not add new hard-coded user-facing text
  to widgets.
- Arabic is RTL. Check layout changes for direction-dependent assumptions.

## 7. Local workflow

Before a change:

1. Run `git status --short` and leave unrelated changes untouched.
2. Use `rg` to find the current implementation, tests, and text first.
3. Change the smallest layer that correctly handles the requirement.
4. Add or update focused regression tests alongside the change.

After a change:

```bash
dart format lib test tool
flutter analyze --no-pub
flutter test
dart run tool/validate_translations.dart
```

Not every command is needed for every change: for an isolated runtime change,
run its targeted test first; for ARB changes, also run `flutter gen-l10n`.
Complete rules and targeted test commands are in the
[change playbooks](change-playbooks.md).

## 8. Further documentation

- `AGENTS.md`: binding repository instructions and standard commands.
- `docs/WIKI.md`: how the block model, compiler, and runtime work.
- `docs/node-ui-and-logic.md`: file-by-file guide for native nodes.
- `docs/plugins/README.md`: Plugin SDK and repository format.
- `docs/localization/README.md`: runtime translations.
- `docs/RELEASING.md`: release, signing, and publishing process.
