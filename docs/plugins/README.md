# NodeQL Plugin SDK v1

NodeQL plugins are independent, declarative packages. A plugin is not compiled
into the Flutter application and does not need Dart or the Flutter SDK. Version
1 plugins add localized visual blocks and compile them to SQL templates.

## Quick start

1. Copy `examples/plugins/com.example.text-tools/plugin.json`.
2. Change the reverse-domain `id`, metadata, blocks, and SQL templates.
3. Validate the file against `docs/plugins/plugin.schema.json`.
4. In NodeQL, open **Settings > Manage Plugins > Install plugin.json**.
5. Reload plugins. The blocks appear in the Plugins palette.

More complete examples are listed in
[`examples/plugins/README.md`](../../examples/plugins/README.md).

During development, set `NODEQL_PLUGIN_DIR` to a directory containing plugin
folders. Each folder must contain a `plugin.json` file:

```text
my-plugins/
  com.example.text-tools/
    plugin.json
```

NodeQL stores installed plugins in its platform-specific application support
directory under `nodeql_plugins/<plugin-id>/plugin.json`.

## Manifest

Required top-level fields:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Must be `1`. |
| `id` | Stable reverse-domain ID, for example `com.example.text-tools`. |
| `name` | Human-readable plugin name. |
| `version` | Semantic version such as `1.2.0`. |
| `blocks` | One or more block definitions. |

Optional fields are `minNodeQlVersion`, `author`, `description`, `homepage`,
`license`, and `capabilities`. The only v1 capability is `sql.compile`.

Plugin and block IDs are persisted in project files. Never reuse an ID for a
different behavior. Increase `version` whenever behavior changes.

## Blocks

Each block supports:

| Field | Meaning |
| --- | --- |
| `id` | Stable lowercase block ID. |
| `shape` | `statement`, `value`, or `container`. |
| `label` | Text or locale map. Use `[inputName]` for editable UI slots. |
| `description` | Text or locale map shown as block help. |
| `color` | Optional `#RRGGBB` color. |
| `inputs` | Typed input definitions with defaults. |
| `sql` | SQL template using `{{inputName}}`. |

Container blocks may use `{{children}}` in the SQL template. Inputs omitted
from a label are appended automatically as editable slots.

Input types:

- `identifier`: validates SQL identifiers such as `users` or `main.users`.
- `number`: accepts only numeric values.
- `string`: emits a quoted SQL string and escapes single quotes.
- `sql`: inserts raw SQL. Use only where arbitrary expressions are intended.

Example:

```json
{
  "id": "ilike",
  "shape": "statement",
  "label": {
    "en": "[column] contains [pattern]",
    "de": "[column] enthält [pattern]"
  },
  "description": {
    "en": "Case-insensitive text comparison.",
    "de": "Textvergleich ohne Beachtung der Groß-/Kleinschreibung."
  },
  "color": "#7C3AED",
  "inputs": [
    {"name": "column", "type": "identifier", "default": "name"},
    {"name": "pattern", "type": "string", "default": "%node%"}
  ],
  "sql": "{{column}} ILIKE {{pattern}}"
}
```

## Compatibility and errors

Set `minNodeQlVersion` when a plugin relies on a newer host API. NodeQL rejects
unsupported schema versions, capabilities, malformed IDs, invalid defaults,
unknown template placeholders, duplicate plugin/block IDs, manifests larger
than 1 MiB, and incompatible host versions.

Projects retain the plugin ID, block ID, and plugin version. If a plugin is
missing, NodeQL keeps the block data and reports a compiler warning rather than
silently replacing its behavior. A version change also produces a warning.

## Security model

Plugin API v1 does not load Dart libraries, native libraries, scripts, or
executables. It only parses validated JSON and expands SQL templates. Generated
SQL runs through the same database execution path and confirmation behavior as
built-in blocks. The `sql` input type is intentionally unrestricted; plugin
authors should prefer `identifier`, `number`, and `string`.

Arbitrary executable plugins require a separate sandboxed protocol and are not
part of API v1.
