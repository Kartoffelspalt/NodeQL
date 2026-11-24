# Web preview

The NodeQL website serves the Flutter demo at `https://www.nodeql.org/demo/`.
Build and upload it for that exact URL prefix:

```sh
flutter pub get
flutter build web --release --base-href /demo/ --no-web-resources-cdn --web-content-hash --pwa-strategy=none
```

Upload the **contents** of `build/web/` into the website's `demo/` directory,
so the start page is `/demo/index.html`. Keep the entire `assets/` and
`canvaskit/` directories. Check that the deployed `index.html` contains
`<base href="/demo/">` and that the `main.dart.<hash>.js` file it references is
available. The loader is inlined in `index.html`. Serve `index.html` with
`Cache-Control: no-cache` so browsers revalidate it after a deployment.
On Apache, install `tool/web_demo_apache.htaccess` as `demo/.htaccess` (merge
with any existing rules) to revalidate the entry page and compress JavaScript
and WebAssembly. The host needs `mod_filter`, `mod_deflate`, and `mod_headers`
with `AllowOverride FileInfo`. Check `Content-Encoding: gzip` on the large
files with `curl --compressed -I` after deployment.
A build with `<base href="/">` requests the start files from the website root.
Use the base path of your own installation if you deploy the demo elsewhere.
Opening `index.html` directly as a local file is not supported.

A fresh browser session opens directly in **Simple Mode** with `nodeql_demo.db`
connected and the **Top Math scores** query already built from editable blocks.
The Help button opens the introduction when wanted.
The database contains six students and twelve Math/Physics scores. The query
joins `students` with `scores`, filters Math results, sorts by score, and shows
Alice (97), Ben (94), and Clara (91) immediately in the output preview.
Restoring an existing project within the tab keeps its workspace and database;
the demo is only loaded when there is no saved project. The small preview in
`web/nodeql.codespiresolutions.digital.html` starts with the same example and
Simple Mode.

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
flutter build web --release --base-href /demo/ --no-web-resources-cdn --web-content-hash --pwa-strategy=none
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
