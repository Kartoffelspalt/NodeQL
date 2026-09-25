# NodeQL v0.4.1 — SQLite Workbench & Workflow Improvements

NodeQL v0.4.1 substantially improves the visual SQLite workflow, result
handling, workspace layout, and settings experience.

## SQLite workflow

- Added a catalog of SQLite functions for use directly in visual queries.
- Added `datetime(..., 'unixepoch')` support to turn Unix timestamps into
  readable dates and times.
- Added per-column aliases directly in the SELECT column picker, including
  multiple aliases in the same query.
- Improved query compilation for aliases and qualified columns, preventing
  ambiguous-column errors in joins.
- Refined node interaction so embedded column and function reporters stay
  selectable and editable.

## Result table and workspace

- Added fullscreen mode for query-result tables.
- Added result export as CSV, JSON, and TSV for reuse in other tools.
- Unified the visual design of SQL command output and result tables.
- Added a live database preview and improved database-browser workflows.
- Reworked the resizable workbench panels with a responsive overlay and
  smooth, cross-platform size transitions.

## Settings and learning

- Redesigned settings as a fullscreen, Apple-inspired experience with
  dedicated sections for Accessibility, Motion, Display, and Personalization.
- Improved the integrated SQLite Workshop, learning paths, practice area, and
  workshop database.

## Reliability

- Restored reliable autosave after workspace changes.
- Fixed invalid rollback arguments during query execution.
- Fixed scrollbar controller assertions in resizable views.
- Fixed Material and ink rendering warnings in selectable repository entries.
- Improved desktop runner behavior on Linux and Windows.

## Quality

- `flutter analyze` completed without issues.
- 219 automated tests passed.
