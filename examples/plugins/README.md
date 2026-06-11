# NodeQL Example Plugins

Every subdirectory contains an independent `plugin.json` that can be installed
through **Settings > Manage Plugins > Install plugin.json**.

| Plugin | Highlights |
| --- | --- |
| `com.example.text-tools` | Case-insensitive matching and transactions |
| `dev.nodeql.analytics` | Ranking, running totals, moving averages, lag |
| `dev.nodeql.json-toolkit` | SQLite JSON extraction, validation, arrays |
| `dev.nodeql.data-quality` | Profiling, duplicate detection, null checks |
| `dev.nodeql.privacy-tools` | Email, phone, and generic value masking |
| `dev.nodeql.sqlite-power` | CTEs, query plans, upserts, date series |

The SQL examples target SQLite, which is NodeQL's current local runtime.
Plugins remain plain JSON packages and can be adapted to other SQL dialects.
