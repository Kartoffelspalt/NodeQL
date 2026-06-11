# NodeQL Plugin SDK v1

## Commit Description

### Subject

```text
Add external Plugin SDK v1 with example plugin library
```

### Body

```text
- add independent JSON-based plugins without requiring Dart or Flutter
- add manifest validation, version compatibility checks, and safe typed inputs
- integrate plugin blocks with the palette, workspace, and SQL compiler
- add plugin installation, reload, diagnostics, and uninstall management
- preserve plugin identity and version metadata in saved projects
- warn about missing plugins and incompatible plugin block versions
- add Plugin SDK documentation and a JSON Schema
- add six example plugins containing 22 analytics, JSON, data quality,
  privacy, SQLite, text, and transaction blocks
- add tests for loading, validation, conflicts, rendering, and compilation
```

## Release Description

NodeQL now supports independent external plugins.

Plugin developers no longer need to modify the NodeQL source code or create a
Dart package. A plugin is distributed as a validated `plugin.json` manifest and
can provide localized visual blocks, custom colors, editable inputs, SQL
expressions, complete statements, and container behavior.

### Plugin Management

Plugins can be installed and managed directly through:

**Settings > Manage Plugins**

The manager displays installed plugins and loading errors and supports
installation, reloading, and removal. During development, plugin authors can
also use the `NODEQL_PLUGIN_DIR` environment variable.

### Safe, Stable Plugin API

Plugin SDK v1 uses a declarative execution model. NodeQL does not load
third-party Dart code, native libraries, or arbitrary executables.

The loader validates:

- manifest and semantic versions
- minimum NodeQL version
- plugin and block IDs
- capabilities and supported fields
- input defaults and SQL placeholders
- duplicate plugins and blocks
- the 1 MiB manifest size limit

Projects store stable plugin, block, and version identifiers. Missing plugins
do not destroy project data; NodeQL retains the blocks and reports a compiler
warning.

### Included Example Plugins

This release includes six ready-to-install examples with 22 blocks:

- **Analytics Lab:** dense rankings, running totals, moving averages, and
  previous-value comparisons
- **Data Quality Inspector:** duplicate reports, NULL profiling, range checks,
  and completeness scores
- **JSON Toolkit:** JSON extraction, validation, array inspection, and updates
- **Privacy Tools:** email, phone, and generic value masking
- **SQLite Power Pack:** query plans, upserts, recursive date series, and CTEs
- **Text Tools:** case-insensitive matching and transaction containers

The examples are available under `examples/plugins/` and can be installed
individually through the plugin manager.

### Developer Resources

- Plugin guide: `docs/plugins/README.md`
- JSON Schema: `docs/plugins/plugin.schema.json`
- Example library: `examples/plugins/README.md`

Automated tests cover manifest validation, compatibility checks, SQL template
rendering, missing plugins, version changes, and conflict-free loading of all
included examples.
