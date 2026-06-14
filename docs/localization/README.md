# NodeQL Community Localization

English in `assets/translations/en.json` is the source of truth for runtime
translation keys. Flutter's generated Material, Cupertino, and Widgets
localizations remain enabled for platform controls.

English and the current partial German catalog are bundled with the app.
Additional reviewed languages are installed from the published manifest.

## GitHub contribution workflow

1. Fork the NodeQL repository.
2. Add or update `translations/<locale>.json`.
3. Run the translation validator locally.
4. Open a pull request with the changed language package.
5. Maintainers review wording, placeholders, schema, and licensing.
6. Only reviewed and merged packages are published for the app.

No external translation account, write API, or client-side access token is
required. Contributors use the normal GitHub pull request review process.

## Package rules

- Schema version is `1`.
- Locale tags use `de` or `de-DE` form.
- Revision numbers only increase.
- Files are limited to 2 MiB.
- Unknown keys are ignored by the app.
- Missing keys fall back to English.
- Placeholders must exactly match the English source.
- The manifest records the exact UTF-8 byte size and SHA-256 of every package.

Validate translations before opening a pull request:

```bash
dart run tool/validate_translations.dart translations
```

The `Validate translations` GitHub Actions workflow runs the same check for
every relevant pull request. After merge, the `Publish translations` workflow
generates the manifest and deploys reviewed packages to GitHub Pages.

Translations are contributed under CC BY 4.0. Contributors must only submit
text they are entitled to license. Maintainers can reject machine-generated,
offensive, misleading, or technically invalid translations.

## Publishing downloads

Reviewed packages can be published as static files with GitHub Pages. Build
NodeQL with the public manifest and this contribution guide:

```bash
flutter build macos \
  --dart-define=NODEQL_TRANSLATION_MANIFEST_URL=https://kartoffelspalt.github.io/NodeQL/translations/translation-manifest.json \
  --dart-define=NODEQL_TRANSLATION_CONTRIBUTION_URL=https://github.com/Kartoffelspalt/NodeQL/blob/master/docs/localization/README.md
```

See [`translation-manifest.example.json`](translation-manifest.example.json).
The app performs unauthenticated HTTPS reads and accepts only
`kartoffelspalt.github.io` and `raw.githubusercontent.com` by default.
