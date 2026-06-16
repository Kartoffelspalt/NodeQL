# NodeQL Plugin SDK v1 and v2

NodeQL plugins are independent, declarative packages. A plugin is not compiled
into the Flutter application and does not need Dart or the Flutter SDK. Version
1 plugins add localized visual blocks and compile them to SQL templates.

SDK v2 keeps v1 compatible and adds external data-source adapters plus
installable community repositories. It does not load arbitrary Dart, native
libraries, or executables into NodeQL.

## SDK v2 data sources

Use `schemaVersion: 2` and declare `data-source.http`. A data-source plugin
defines:

- `permissions.networkHosts`: every host it may contact.
- `permissions.secrets`: symbolic secret names requested at runtime.
- `dataSources`: one or more fixed JSON-over-HTTP adapters.

Production adapters must use HTTPS. HTTP is accepted only for local
development bridges on `localhost`, `127.0.0.1`, or `::1`.

The bridge contract is intentionally language- and vendor-neutral:

- `GET schemaPath` returns a JSON object describing available databases,
  collections or tables, fields, and supported operations.
- `POST queryPath` accepts
  `{"query":"...","parameters":{...}}` and returns a JSON object containing
  rows, columns, messages, or structured errors.
- Required secrets are sent as `x-nodeql-secret-SECRET_NAME` headers.
- Responses are limited to 4 MiB.

This allows contributors to maintain MongoDB, Supabase, REST, GraphQL, or
vendor-specific bridges independently. See
`docs/plugins/examples/external-data-source.plugin.json` and validate manifests
against `docs/plugins/plugin-v2.schema.json`.

## Community repositories

The Plugin Dashboard accepts custom repository catalog URLs, similar to Grav's
repository model. Catalogs are static JSON files and must use HTTPS, except for
localhost development.

Every plugin entry includes a manifest URL and mandatory SHA-256 digest.
NodeQL verifies the digest, parses the manifest with the normal SDK validator,
checks ID and version consistency, and only then installs it.

Repository owners can validate catalogs against
`docs/plugins/repository.schema.json`. No custom server API is required.
The `docs/plugins/examples/repository.catalog.json` file demonstrates a
complete catalog with a real SHA-256 digest.

The public NodeQL example plugin repository is available at:

```text
https://kartoffelspalt.github.io/nodeql-example-plugins/repository.catalog.json
```

Add this URL in **Settings > Manage Plugins > Repositories** to test the
repository workflow with the maintained example plugins.

### Publish a repository with GitHub Pages

1. Create a public GitHub repository, for example `nodeql-plugins`.
2. Add `repository.catalog.json` and the referenced plugin manifests.
3. Calculate every manifest digest with
   `shasum -a 256 path/to/plugin.json`.
4. Put the resulting lowercase hash into the catalog entry's `sha256` field.
5. Open **Settings > Pages** in GitHub and deploy from the `main` branch or a
   GitHub Actions Pages workflow.
6. Add the resulting HTTPS URL in NodeQL, for example
   `https://OWNER.github.io/nodeql-plugins/repository.catalog.json`.

Relative `manifestUrl` values are resolved against the catalog URL. A minimal
repository can therefore use this layout:

```text
nodeql-plugins/
  repository.catalog.json
  plugins/
    org.example.mongo.plugin.json
```

```json
{
  "schemaVersion": 1,
  "name": "My NodeQL Plugins",
  "plugins": [
    {
      "id": "org.example.mongo",
      "name": "MongoDB Bridge",
      "version": "2.0.0",
      "description": "Connects NodeQL to a MongoDB HTTP bridge.",
      "manifestUrl": "plugins/org.example.mongo.plugin.json",
      "sha256": "64-character-lowercase-sha256"
    }
  ]
}
```

The catalog and remote manifests must use HTTPS. During local development,
NodeQL also accepts HTTP URLs on `localhost`, `127.0.0.1`, and `::1`.

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
| `schemaVersion` | `1` for classic plugins or `2` for SDK v2. |
| `id` | Stable reverse-domain ID, for example `com.example.text-tools`. |
| `name` | Human-readable plugin name. |
| `version` | Semantic version such as `1.2.0`. |
| `blocks` | One or more block definitions. |

Optional fields are `minNodeQlVersion`, `author`, `description`, `homepage`,
`license`, and `capabilities`. v1 supports `sql.compile`; v2 also supports
`data-source.http`, `permissions`, and `dataSources`.

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

NodeQL gives every plugin shape a dedicated extension silhouette:

- `statement`: chainable block with cut corners.
- `value`: faceted reporter without top or bottom chain connectors.
- `container`: C-shaped block for nested child statements.

The configured plugin color remains unchanged. A small extension rail
distinguishes community plugin blocks from built-in SQL blocks without adding
fields to the public manifest format.

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
  "sql": "LOWER({{column}}) LIKE LOWER({{pattern}})"
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

Arbitrary executable plugins remain unsupported. SDK v2 uses a constrained
HTTP protocol so external connectors can be maintained independently without
running third-party code inside the NodeQL process.
