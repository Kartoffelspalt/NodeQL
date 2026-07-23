# Changelog

All notable changes to NodeQL are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- No unreleased changes yet.

## [0.3.3] - 2026-07-13

### Added

- Added per-project autosave. It is selected when a project is created and
  saves workspace changes after a short delay.
- Added automatic creation of a `.nodeql` project file for new projects and
  unique file names when the chosen name already exists.
- Added `Cmd+S` and `Ctrl+S` project saving shortcuts.
- Added a project-file upgrade flow for legacy workspace, NodeQL, and ScratchQL
  project formats.
- Added timestamped project backups before a legacy file is upgraded.
- Added localized German and English project-upgrade and compatibility dialogs.
- Added project upgrade service tests for current, legacy, incompatible, and
  malformed project files.
- Added the NodeQL architecture wiki in English.

### Changed

- Centered node labels vertically and refined inline text and input-slot
  spacing, while preserving the specialized JOIN layout.
- Increased the available width for nodes and palette previews so long labels
  and values no longer clip.
- Updated the macOS project configuration to remove obsolete CocoaPods
  integration.
- Updated `build_runner` to `2.15.1` and bumped NodeQL to `0.3.3+3`.

### Fixed

- Prevented project-file overwrite collisions during project creation.
- Prevented loading or overwriting project files created by a newer,
  incompatible NodeQL version.

## [0.3.2] - 2026-07-05

- Replaced the SQL wildcard `*` with localized, beginner-friendly wording such
  as "Alles" in Simple Mode while preserving the generated SQL.
- Added an exclusive "Everything" option above the column list: selecting it
  disables individual columns in both Simple and Advanced Mode.
- Persisted the selected Simple or Advanced editing mode across app restarts.
- Added a screenshot gallery near the top of the public README with dedicated
  contribution guidance for future app images.
- Added a trademark policy that separates the MIT-licensed source code from
  the NodeQL name, logo, and project identity.
- Added a persistent White Mode and updated the workbench, SQL output,
  dropdowns, and interactive tutorial to use theme-aware surfaces and readable
  foreground colors.
- Fixed inline table and JOIN dropdown positioning so menus open beneath their
  selected block slots instead of at a window edge.
- Fixed SELECT table spacing and JOIN type overlap in visual blocks.
- Updated JOIN behavior so CROSS and NATURAL joins omit the ON condition,
  while condition-based joins retain it.
- Added a vertical separator to JOIN blocks to make the boundary between the
  source table and each appended table visible.
- Updated Linux, macOS, and Windows runners to start NodeQL maximized.
- Added a localized, interactive seven-step onboarding tutorial with visual
  block examples, knowledge checks, persisted first-run completion and a
  permanent help entry in the workbench.
- Refined the `EXECUTE QUERY` trigger with a cleaner start-cap silhouette,
  integrated play marker and improved label spacing.
- Simplified the `EXECUTE QUERY` trigger to a straight top edge while keeping
  its circular play marker.
- Added Scratch-style nested reporter inputs: rounded aggregate functions,
  column selectors and text values can now be dropped directly into compatible
  input slots and compile recursively.
- Added Plugin SDK v2 contracts for permission-declared HTTP data sources,
  persistent custom plugin repositories, SHA-256-verified installs, and
  repository management in the Plugin Dashboard.
- Reworked the SQL command panel with a dedicated header, non-overlapping copy
  action, and content-responsive height.
- Restored complete `SELECT ... FROM ...` defaults while retaining support for
  separately docked FROM clauses.

### Added

- Added SQL-aware block shapes for statement heads, clauses, joins, set
  operators, expressions, containers, and terminal statements.
- Added dedicated plugin statement, value, and container silhouettes while
  preserving compatibility with existing plugin manifests and projects.
- Added two-row JOIN layouts with a dedicated condition row and distinct
  visuals for CROSS, NATURAL, and SELF joins.
- Added syntax-aware docking for valid SELECT, FROM, JOIN, WHERE, GROUP BY,
  HAVING, ORDER BY, and set-operator sequences.
- Added a representative SQL query as the initial workspace instead of the
  legacy motion-block example.
- Added local-first runtime translation packages with validation, SHA-256
  verification, offline caching, persisted language selection, and English
  fallback.
- Added GitHub pull request translation contributions and GitHub Pages
  publishing for reviewed packages.
- Added CI quality gates and deterministic Linux, macOS, and Windows release
  packaging with SHA-256 checksums.
- Added public contribution, security, privacy, conduct, and release policies.
- Added Plugin SDK v1 for independent, manifest-based NodeQL plugins without
  requiring Dart or Flutter.
- Added runtime discovery of `plugin.json` manifests from the NodeQL plugin
  directory and the optional `NODEQL_PLUGIN_DIR` development override.
- Added a plugin manager under **Settings > Manage Plugins** for installing,
  reloading, inspecting, and uninstalling plugins.
- Added localized plugin labels, descriptions, custom colors, typed inputs,
  statement blocks, value blocks, and container blocks.
- Added SQL template compilation with support for `identifier`, `number`,
  `string`, and raw `sql` inputs.
- Added compatibility checks for schema versions, NodeQL versions,
  capabilities, duplicate IDs, invalid defaults, unknown fields, and malformed
  templates.
- Added project-safe plugin references using stable plugin IDs, block IDs, and
  plugin versions.
- Added warnings when a required plugin is missing or when a project block was
  created with another plugin version.
- Added Plugin SDK documentation and a JSON Schema for editor validation.
- Added six installable example plugins with 22 blocks:
  - Analytics Lab
  - Data Quality Inspector
  - JSON Toolkit
  - Privacy Tools
  - SQLite Power Pack
  - Text Tools
- Added automated tests for manifest validation, compatibility handling,
  example loading, SQL rendering, missing plugins, and version changes.

### Changed

- Split newly created SELECT and FROM blocks while preserving compilation of
  existing projects that store the source table directly on SELECT.
- Updated workspace layout calculations for variable block heights.
- Replaced the previous translation service integration with a GitHub-only
  contribution and distribution workflow.
- Standardized release artifacts and platform metadata on the NodeQL name.
- Limited the first public release pipeline to supported desktop platforms.
- Updated the SQL compiler to resolve and compile external plugin blocks.
- Updated the block palette and workspace drag-and-drop flow to retain plugin
  metadata and default input values.
- Updated the workbench to render plugin-specific labels, editable slots,
  descriptions, shapes, and colors.
- Added `path` as a direct dependency for portable plugin directory handling.

### Security

- Translation downloads require HTTPS, an approved GitHub host, matching
  package metadata, an exact byte size, and a matching SHA-256 digest.
- Releases are created only after all quality and desktop build jobs succeed.
- Plugin API v1 is declarative and does not execute third-party Dart code,
  native libraries, scripts, or executables.
- Plugin manifests are limited to 1 MiB and reject unsupported or unknown
  fields.
- Typed SQL inputs validate identifiers and numbers and safely quote string
  values.
