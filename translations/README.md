# Runtime translations

Reviewed runtime language packages are stored in this directory as
`<locale>.json`. See [`docs/localization/README.md`](../docs/localization/README.md)
for the package format and pull request workflow.

The desktop release workflow combines these reviewed overrides with AI-generated
translations of missing or changed English messages. Generated packages are
build artifacts; they are bundled in every desktop installer and published in
the release's language archive and download catalog. Provider configuration and
local dry-run commands are described in the guide above.
