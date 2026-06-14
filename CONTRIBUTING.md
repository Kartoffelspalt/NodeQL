# Contributing to NodeQL

## Before opening a pull request

1. Open an issue for large behavioral or architectural changes.
2. Keep changes focused and preserve local-first operation.
3. Add or update tests for user-visible behavior.
4. Run:

```bash
flutter pub get
flutter gen-l10n
dart format lib test tool
flutter analyze
flutter test
dart run tool/validate_translations.dart
```

Pull requests must pass CI and may be revised or closed when they weaken
offline behavior, validation, accessibility, security, or project
compatibility.

Translation contributions follow
[`docs/localization/README.md`](docs/localization/README.md). Plugin
contributions follow [`docs/plugins/README.md`](docs/plugins/README.md).

By contributing code, you agree to license it under the MIT License. Runtime
translation contributions are licensed under CC BY 4.0 as documented in the
localization guide.
