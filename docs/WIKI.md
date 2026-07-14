# NodeQL Wiki

This wiki explains how NodeQL works: from the visible workbench, through the
internal block data model, to SQL execution against a local SQLite database.

## Summary

NodeQL is a local-first desktop application for learning, designing, and running
SQL with visual blocks. Instead of writing SQL directly in a text editor, users
assemble SQL building blocks visually. NodeQL translates that block structure
into SQL, shows the generated query, and can execute it against a local SQLite
database.

The main flow is:

```text
Block palette -> Workspace -> Block tree -> SQL compiler -> SQL preview
              -> SQLite runtime -> Result table / status message
```

Projects, settings, installed plugins, and databases stay on the user's device.
NodeQL is not a cloud service and not a machine-learning project.

## What You See in NodeQL

The central interface is the workbench. It is made up of several areas:

| Area | Purpose |
| --- | --- |
| Block palette | Built-in SQL, control, operator, and plugin blocks |
| Workspace | Canvas where blocks are placed, connected, and edited |
| SQL preview | Shows the SQL statement generated from the blocks |
| Database area | Connects or creates local SQLite databases |
| Result area | Shows execution messages and result rows |
| Settings | Language, theme, plugins, repositories, and other app options |

The workbench is designed as a visual SQL builder. Users do not only see the
final query; they also see the structure that produced it.

## The Block Model

Every block is stored internally as a `BlockNode`. A block stores:

- a unique `id`
- a `type`, such as `sqlSelect`, `sqlWhere`, or `sqlJoin`
- a `position` in the workspace
- optional values in `inputs`
- the next block in `next`
- nested child blocks in `children`

This allows NodeQL to represent both simple linear queries and nested
structures. A typical chain conceptually looks like this:

```text
EXECUTE QUERY
  -> SELECT [columns]
  -> FROM [table]
  -> WHERE [predicate]
  -> ORDER BY [column]
```

The `eventGreenFlag` start block is the executable entry point. Blocks that are
floating in the workspace and are not attached below such a start block are not
treated as executable queries by the SQL compiler.

## How Blocks Become SQL

SQL generation happens in the `SqlCompiler`. It receives the root blocks from
the workspace and walks through the executable block chains.

Simplified, the compiler works like this:

1. Find root blocks.
2. Compile only chains below `EXECUTE QUERY`.
3. Translate each block type into an SQL fragment.
4. Append `next` blocks.
5. Insert `children` from container or reporter blocks.
6. Render plugin blocks through their SQL templates.
7. Collect warnings when something is not executable.
8. Add a semicolon for each generated statement.

Examples of built-in block translations:

| Block type | SQL fragment |
| --- | --- |
| `sqlSelect` | `SELECT ...` |
| `sqlFrom` | `FROM table_name` |
| `sqlWhere` | `WHERE predicate` |
| `sqlJoin` | `JOIN table ON condition` |
| `sqlGroupBy` | `GROUP BY column` |
| `sqlOrderBy` | `ORDER BY column direction` |
| `sqlCount` | `COUNT(column)` |
| `sqlInsert` | `INSERT INTO ...` |
| `sqlUpdate` | `UPDATE ... SET ...` |
| `sqlDelete` | `DELETE FROM ...` |

The output is normal SQL syntax. NodeQL does not hide SQL; it makes the
translation from visual structure to real SQL text visible.

## Why There Is an EXECUTE QUERY Start Block

NodeQL distinguishes between blocks that merely exist in the workspace and
blocks that should actually be executed. The start block marks that boundary.

This has three benefits:

- Users can prepare blocks without executing them immediately.
- Multiple query chains can exist in one project.
- The compiler can clearly decide which chain should generate SQL.

If an SQL block is floating freely in the workspace, NodeQL reports a warning
instead of executing it silently.

## Slots, Inputs, and Reporters

Many blocks have editable slots. A slot is a visible input field that is stored
internally in `inputs`. Examples:

```text
SELECT [columns]
FROM [table]
WHERE [left] [operator] [right]
```

Reporter blocks provide values for other blocks. For example, an aggregate block
such as `COUNT(column)` can be inserted into a SELECT slot. This creates a
structure that is closer to SQL expressions than plain text fields.

## Workspace and Snapping

The workspace manages where blocks are placed and how they are connected. When a
block is dragged, NodeQL checks compatible docking points. If a block is close
enough to an allowed position, it snaps into place.

Two important relationships are created:

- `next`: The block comes after another block in the same chain.
- `children`: The block sits inside a container block or is used as an embedded
  expression.

Snapping is not only visual. It defines the actual data structure that the
compiler reads later.

## SQL Preview

The SQL preview is a core part of NodeQL. It directly shows which SQL statement
is produced by the current block structure.

It serves three purposes:

- Learning: users see which SQL syntax belongs to which block.
- Checking: mistakes in order, column names, or predicates become visible
  faster.
- Transparency: before execution, users can see exactly which query will be sent
  to SQLite.

NodeQL is therefore not a replacement for understanding SQL. It is an interface
that makes SQL structure visible and editable.

## Local SQLite Runtime

Execution happens in the `SqlRuntime`. It uses the Dart `sqlite3` package, so it
does not depend on `/usr/bin/sqlite3` or an external system SQLite CLI.

The runtime flow is:

1. The user selects a `.db`, `.sqlite`, or `.sqlite3` file.
2. NodeQL copies or opens the file through a controlled local path.
3. The runtime reads the schema from `sqlite_schema`.
4. For each table, columns are read with `PRAGMA table_info(...)`.
5. On execution, the current SQL statement is sent to SQLite.
6. Result rows are capped for preview display.
7. Status messages and rows are shown in the result area.

Write statements receive additional protection. Before potentially mutating SQL
statements, NodeQL creates a snapshot. If execution fails, the database is
restored from that snapshot.

## Database Schema in the UI

After a database is connected, NodeQL knows its tables and columns. That schema
can be used in the interface so users can find valid table and column names more
quickly.

NodeQL reads only user tables:

```sql
SELECT name
FROM sqlite_schema
WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
ORDER BY name
```

Internal SQLite tables are hidden.

## Project Files

A NodeQL project stores the visual workspace as JSON. The important part is that
NodeQL does not only save the generated SQL text; it saves the block structure.

Stored data includes:

- block types
- positions
- input values
- chains through `next`
- nested blocks through `children`
- plugin references

This allows a project to be loaded later as a visual workspace and edited again.

NodeQL saves current project files with a format identifier and version number.
When a supported older workspace, NodeQL, or ScratchQL project is opened,
NodeQL offers an upgrade. Confirming the upgrade first creates a timestamped
backup beside the original file and then writes the project in the current
format. Files created by a newer NodeQL version are not overwritten.

Autosave is configured per project during project creation. When enabled, it
stores workspace changes locally after a short delay; normal project saves are
also available through `Cmd+S` on macOS or `Ctrl+S` on Windows and Linux.

## Plugin System

Plugins extend NodeQL with new blocks without being compiled into the Flutter
application. A plugin is a declarative `plugin.json` manifest.

A plugin block defines, among other things:

- a stable plugin ID
- block IDs
- labels and descriptions
- shape and color
- inputs
- SQL templates
- optional minimum NodeQL version

During compilation, NodeQL detects whether a block comes from a plugin. If it
does, the block is not handled by a fixed Dart switch case. Instead, the
plugin's SQL template is rendered.

The central distinction is:

```text
Built-in block -> Dart switch/case in SqlCompiler
Plugin block   -> Manifest + SQL template
```

## Plugin Repositories

NodeQL can install community plugin catalogs from static HTTPS URLs. The public
example repository is:

```text
https://kartoffelspalt.github.io/nodeql-example-plugins/repository.catalog.json
```

The catalog points to individual `plugin.json` manifests. NodeQL checks:

- whether the catalog is valid
- whether the manifest URL is reachable
- whether the SHA-256 hash matches the manifest file
- whether the manifest matches the schema
- whether plugin ID and version are consistent
- whether the NodeQL version is compatible

The SHA-256 hash is calculated over the concrete `plugin.json`, not over the
plugin folder.

## Data Source Plugins in SDK v2

SDK v2 allows declarative external data sources through fixed JSON-over-HTTP
adapters. This means NodeQL still does not load third-party code, but it can
communicate with bridges through clearly defined HTTP endpoints.

A data source plugin declares:

- allowed network hosts
- required secrets
- schema endpoint
- query endpoint
- fixed request and response structure

This allows MongoDB, Supabase, REST, or GraphQL bridges to be maintained
externally while NodeQL itself only executes the constrained, explicit contract.

## Localization

Visible text comes from ARB files under `lib/l10n/` and is generated into
`lib/localization/generated/`.

Supported languages:

- German
- English
- French
- Spanish
- Italian
- Portuguese
- Turkish
- Arabic with RTL
- Japanese
- Korean
- Chinese

After text changes, run:

```bash
flutter gen-l10n
```

At runtime, NodeQL can also use validated community language packages. These
packages are checked for schema, size, metadata, placeholders, and hashes.

## Code Architecture

The most important areas are:

| Path | Purpose |
| --- | --- |
| `lib/core` | App bootstrap, theme, update checks |
| `lib/localization` | Language, catalogs, runtime translations |
| `lib/domain` | Project and block models |
| `lib/data` | JSON persistence and default project |
| `lib/engine/block` | Block types, block nodes, syntax, and reporters |
| `lib/engine/plugins` | Plugin manifests, loader, repository logic |
| `lib/engine/runtime` | General runtime models and scheduler |
| `lib/engine/workspace` | Workspace models and docking service |
| `lib/features/workbench` | Visible workbench, SQL mode, compiler, runtime |
| `lib/ui` | Shell and app entry |
| `test` | Unit, widget, runtime, plugin, and workspace tests |

State management is based on Riverpod. Routing uses `go_router`. The relevant
logic for block structure, SQL compilation, plugin manifests, and SQLite
execution is testable separately from the UI.

## Security and Privacy

NodeQL is local-first. Its design avoids unnecessary network dependencies.

Important security boundaries:

- No analytics.
- No account tracking.
- No automatic crash reporting.
- Local SQLite files stay local.
- Plugins do not execute third-party Dart, native, or script code.
- Remote plugin repositories require HTTPS.
- Manifests are validated with SHA-256 and JSON Schema.
- Data source plugins must declare hosts and secrets.

Optional network behavior, such as update checks, plugin catalogs, or community
translations, is documented separately.

## Common Failure Cases

### A Block Does Not Generate SQL

Usually it is not attached below an `EXECUTE QUERY` start block, or it is a
reporter that is only intended to provide input to another block.

### The SQL Looks Incomplete

Check whether `SELECT`, `FROM`, `WHERE`, `JOIN`, and other clauses are connected
in a meaningful chain. The visual order is the compilation order.

### A Database Is Connected, but No Tables Appear

The runtime hides internal SQLite tables. If no user tables exist, NodeQL reports
that the database was loaded but no user tables were found.

### Plugin Installation Fails With 404

The repository catalog is often reachable, but `manifestUrl` points to a file
that does not exist. The path and casing must exactly match the GitHub Pages
layout.

### SHA-256 Does Not Match

After every manifest change, the hash must be recalculated over the referenced
`plugin.json`.

## Development and Tests

Important commands:

```bash
flutter pub get
flutter gen-l10n
dart format lib test tool
flutter analyze
flutter test
dart run tool/validate_translations.dart
flutter run -d macos
```

Targeted tests:

```bash
flutter test test/plugins/plugin_manifest_test.dart
flutter test test/runtime/sql_runtime_test.dart
flutter test test/workspace/workspace_engine_test.dart
flutter test test/workspace/block_syntax_test.dart
```

After changes to block types, the compiler, the runtime, or plugins, add or
update tests in the corresponding subsystem.

## Further Documentation

- `README.md` for the short project overview.
- `docs/plugins/README.md` for Plugin SDK v1 and v2.
- `docs/localization/README.md` for community translations.
- `docs/RELEASING.md` for the release process and signing.
- `docs/node-ui-and-logic.md` for notes about node appearance and logic.
- `CHANGELOG.md` for the change history.
- `PRIVACY.md` for privacy details.
- `SECURITY.md` for security reporting.
