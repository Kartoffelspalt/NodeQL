# NodeQL Community Localization

English in `assets/translations/en.json` is the source of truth for runtime
translation keys. Flutter's generated Material, Cupertino, and Widgets
localizations remain enabled for platform controls.

English and the current partial German catalog are available in development
builds. Desktop releases also bundle AI-generated language packages. The same
packages are published as release assets and through the download manifest.

## AI translations during GitHub releases

The `Desktop Release` workflow generates language packs with **Google Gemini**
**once**, after the quality gates and before the Linux, macOS, and Windows builds.
All three builds
include the same validated packages in `assets/translations/`, so they work
offline from the first launch. No AI API key is embedded in the app.

Configure **Settings → Secrets and variables → Actions**:

| Type | Name | Value |
| --- | --- | --- |
| Secret | `GEMINI_API_KEY` | Your Google AI Studio / Gemini API key |
| Variable (optional) | `NODEQL_TRANSLATION_MODEL` | Gemini model ID; defaults to `gemini-3.8-flash` |
| Variable (optional) | `NODEQL_TRANSLATION_LOCALES` | Comma-separated locale tags; defaults to `de,fr,es,it,pt,tr,ar,ja,ko,zh` |
| Variable (optional) | `NODEQL_TRANSLATION_CONCURRENCY` | Concurrent batches, 1–8; defaults to 3; use 1 for tight rate limits |

For example, extend the locale list with `nl,pl,uk,hi,id,vi,he,fa`.
Use locale tags supported by Flutter's platform localizations. Unknown native
language names are displayed as their locale tags. Store the API key as an
Actions secret named `GEMINI_API_KEY`; it is required only by the translation
generation step. No custom API endpoint is needed.

Gemini receives only the English catalog strings and translation instructions.
The integration calls Google's native
[`generateContent` API](https://ai.google.dev/api/generate-content), with a JSON
schema requiring exactly the requested translation keys. The API key is sent
in the `x-goog-api-key` header, never in the request URL or build artifacts.
SQL keywords, product names, placeholders, and code must retain their meaning.
Requests use batches of 40 strings with up to three batches in parallel by
default. Invalid output, throttling, and server errors are retried up to three
attempts; a failed batch stops the release.
Blocked Gemini responses fail immediately. Missing credentials fail when an
API call is needed, rather than silently publishing incomplete packages.
Configure Gemini API billing and rate limits before the first run.

Generated packages and per-message English source hashes are cached between
release runs. Only new or changed English messages need another API call.
Changing the Gemini model or target locale configuration starts a new cache.
Gemini uses its own cache namespace; old provider caches are not reused.
The release build number becomes the package revision, so it must continue to
increase. Cache eviction merely requires a full translation again. After
changing translation instructions, increment `translationPromptVersion` in
`tool/src/ai_translation_generator.dart` to invalidate generated wording.

Messages in reviewed `translations/<locale>.json` files always take precedence
over generated wording. Update reviewed translations when English source text
changes; incompatible placeholders fail validation and require correction.
AI packages are checked for schema, completeness, exact keys, empty strings,
and placeholders (including repeated occurrences). These checks do not replace
human review of translation quality. Corrections can be contributed through
the pull request workflow below and are included in the next release.

Each release includes `nodeql-translations-X.Y.Z.tar.gz` containing the language
packages and their SHA-256 manifest. After the GitHub release succeeds, the
reusable `Publish translations` workflow deploys that exact catalog to GitHub
Pages. Configure Pages with **GitHub Actions** as its source. An unrelated
translation commit no longer replaces the release catalog. If Pages deployment
fails, the installers and archive remain usable; rerun the failed job. The
workflow can also be dispatched manually with a successful release's run ID
while its `translation-packages` artifact is retained.

### Local preview and testing

Inspect the required work without credentials, API requests, or writes:

```bash
dart run tool/generate_translations.dart --revision=12 --locales=fr,pl --dry-run
```

Set `GEMINI_API_KEY` in your local environment, then generate and validate.
Optionally set `NODEQL_TRANSLATION_MODEL` to use another Gemini model:

```bash
dart run tool/generate_translations.dart --revision=12 --locales=fr,pl
dart run tool/validate_translations.dart build/ai-translations/packages
dart run tool/build_translation_site.dart build/ai-translations/packages
```

Use `--help` for output paths, batch size, and source options. Temporary packages
and source hashes stay under ignored `build/ai-translations/`. To include local
packages in an app build, copy the contents of
`build/translation-site/translations/` into `assets/translations/` before building.
Generated files copied there are local build artifacts and should not be
committed. The release workflow performs this step automatically.

## GitHub contribution workflow

1. Fork the NodeQL repository.
2. Add or update `translations/<locale>.json`.
3. Run the translation validator locally.
4. Open a pull request with the changed language package.
5. Maintainers review wording, placeholders, schema, and licensing.
6. The next desktop release uses merged packages as reviewed overrides.

Contributors need no external translation account, write API, or client-side
access token. Maintainers configure the build-time AI provider separately.

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
every relevant pull request. The release workflow generates the manifest and
deploys the combined reviewed and AI-generated packages to GitHub Pages.

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
