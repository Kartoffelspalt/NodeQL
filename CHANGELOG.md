# Changelog

All notable changes to NodeQL are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

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
