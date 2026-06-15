# Plugin SDK v2

## Summary

Plugin SDK v2 extends NodeQL's declarative plugin model without breaking SDK
v1. Community developers can publish visual SQL blocks, external data-source
adapters, and static plugin repositories.

## Data-source adapters

SDK v2 introduces `data-source.http`. Adapters declare:

- allowed network hosts
- required symbolic secrets
- schema and query endpoints
- localized names and descriptions

NodeQL provides a fixed JSON-over-HTTP client. This makes MongoDB, Supabase,
REST, GraphQL, and vendor bridges implementable in any language while keeping
third-party executables outside the NodeQL process.

## Community repositories

The Plugin Dashboard now stores custom repository URLs. Catalogs are refreshed
on demand and list downloadable manifests. NodeQL requires HTTPS for remote
catalogs, limits catalog and manifest sizes, verifies SHA-256, validates the
manifest, and checks catalog ID/version consistency before installation.

## Compatibility

- SDK v1 manifests remain supported.
- Existing project plugin IDs and versions are unchanged.
- SDK v2 manifests use `schemaVersion: 2`.
- HTTP is restricted to localhost development bridges; production uses HTTPS.

## Contributor resources

- `docs/plugins/README.md`
- `docs/plugins/plugin-v2.schema.json`
- `docs/plugins/repository.schema.json`
- `docs/plugins/examples/external-data-source.plugin.json`
- `docs/plugins/examples/repository.catalog.json`
