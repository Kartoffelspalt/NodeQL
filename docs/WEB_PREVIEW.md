# Web preview

NodeQL can be built as a static Flutter web application:

```sh
flutter pub get
flutter build web --release
```

Serve the **contents** of `build/web/` over HTTP or HTTPS. Opening `index.html`
directly as a local file is not supported. To host below a path, build with
`flutter build web --release --base-href /preview/` instead. Keep the complete
assets directory when uploading the build.

The browser preview uses SQLite WebAssembly. Projects, databases, and settings
live in memory for the current tab. **Reloading or closing the tab discards this
session.** Project
and result exports download a file; file imports are copied into session
storage. New projects use a session directory rather than requesting a local
folder. A project export does not include its SQLite database; retain the
original database separately when importing one.

Plugins, workshops, and the table browser are available in the desktop app.
Their buttons in the web preview, including the plugin and workshop settings,
open a notice explaining that the feature is only available in the desktop app.
The notice includes a GitHub button that opens the
[NodeQL repository](https://github.com/Kartoffelspalt/NodeQL) in a new tab.
Desktop functionality and shortcuts remain unchanged. The browser's table
browser keyboard shortcut stays disabled.

Desktop builds continue to use native SQLite, local files, and background
isolates. Browser SQL currently runs on the main event loop; expensive queries
can pause the UI. Remote translation repositories must allow browser requests
through CORS.

## Validation

```sh
flutter analyze
flutter test
flutter test --platform chrome test/platform/web_preview_test.dart
flutter build web --release
```

The `test/assets` symlink exposes app assets to Flutter's browser test server.
Preserve this symlink when checking out the repository.

Set `CHROME_EXECUTABLE` when using a Chromium browser installed at a different
path. For Brave on macOS:

```sh
CHROME_EXECUTABLE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  flutter test --platform chrome test/platform/web_preview_test.dart
```

For interactive development in Brave:

```sh
flutter run -d web-server --web-port 8080
```

Open `http://localhost:8080` in Brave.

## Bundled SQLite module

`assets/sqlite/sqlite3.wasm` is the unmodified `sqlite3.wasm` asset from the
[sqlite3.dart 3.5.2 release](https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-3.5.2).
Its SHA-256 digest is:

```text
13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4
```

The package license is included in `assets/sqlite/LICENSE`. The app pins
`sqlite3` to the version of the bundled WASM module so Flutter SDKs resolve the
same pair. When upgrading SQLite, update both together and rerun the browser
tests.
