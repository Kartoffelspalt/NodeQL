# NodeQL in Rust

Eigenständiger Beginn der nativen Rust-Neuentwicklung. Die Anwendung in diesem
Ordner verwendet kein Flutter, Dart, JavaScript oder WebView. Oberfläche und
Anwendungslogik sind Rust; die SQLite-Engine wird über `rusqlite` als gebündelte
native Bibliothek eingebunden. Die bestehende Flutter-App liegt unverändert im
übergeordneten Projekt.

## Starten

Voraussetzungen: Rust **1.95 oder neuer**, Cargo und die nativen Build-Werkzeuge
der Plattform. Auf macOS werden die Xcode Command Line Tools benötigt. Unter
Linux benötigt der Desktop zusätzlich Wayland/X11 und OpenGL sowie für
Dateidialoge ein XDG Desktop Portal oder Zenity.

```sh
cd nodeql-rust
cargo run --locked
```

Auf macOS kann außerdem ein eigenes App-Bundle gebaut werden:

```sh
sh tools/bundle-macos.sh
```

Ergebnis: `target/release/bundle/NodeQL Rust.app`. Das Bundle verwendet eine
eigene App-Kennung und eine lokale Ad-hoc-Signatur. Es ist noch kein signiertes
und notarisiertes Distributionspaket.

Die Workbench öffnet eine lokale Demo-Datenbank und führt eine Abfrage mit
SELECT, JOIN und ORDER BY aus. „DB laden“ legt eine SQLite-Arbeitskopie im
Anwendungsordner an. Über das NodeQL-Logo lassen sich Projekte öffnen und neue
SQLite-Dateien anlegen.

## Workbench

- Oberfläche nach dem Flutter-Original mit Kategorien, durchsuchbarer Palette,
  Query-Tabs, Puzzle-Blöcken sowie SQL- und Ausgabevorschau.
- Einfach- und Erweitert-Modus, Deutsch und Englisch, vier Farbthemen und
  verschiebbare Vorschaufenster. Auf macOS nutzt die App die Systemschrift.
- Blöcke frei platzieren, an die Abfragekette andocken, abdocken und die
  Arbeitsfläche verschieben oder zoomen. Cmd/Ctrl+Z und Cmd/Ctrl+Umschalt+Z
  machen Änderungen am aktuellen Query rückgängig oder wiederholen sie.
- SQLite-Programme aus allen Query-Tabs, schreibgeschützte Live-Vorschau und
  explizite Ausführung von Daten- und Schemaänderungen mit Rollback bei Fehlern.
- Tabellenbrowser mit Spalten, paginierten Daten, grafischer Tabellenerstellung
  im Einfach-Modus und SQLite-Editor im Erweitert-Modus.
- Vollbild-Ergebnisse mit CSV-, JSON- und TSV-Export. Aus „SQL bearbeiten“
  lassen sich unterstützte Anweisungen in neue Query-Tabs umwandeln.
- Native Dateidialoge, atomisches Speichern und Rückfrage bei ungespeicherten
  Änderungen. Cmd/Ctrl+Enter führt SQLite aus und Cmd/Ctrl+S speichert.

- Mehrere Startketten pro Query-Tab, verschachtelte Reporter, Funktionskatalog
  und Navigation vom erzeugten SQL zu seinen Blöcken.
- Projektwiederherstellung, zuletzt geöffnete Projekte und gespeicherter
  Zoom und Bildausschnitt pro Tab.
- Interaktive Lernpfade mit separat ausgeführter Übungsdatenbank und
  gespeichertem Fortschritt.

Der [Migrationsstand](MIGRATION.md) hält die verbleibenden Unterschiede zu
Flutter fest.

## SQLite-Bibliotheken

| Crate | Aufgabe |
| --- | --- |
| [`nodeql-sqlite-file`](crates/sqlite-file) | Rust-Dateileser ohne externe Abhängigkeiten. Liest Header, `sqlite_schema` und physische Datensätze aus Rowid- und `WITHOUT ROWID`-Tabellen einer stabilen Kopie. |
| [`nodeql-sqlite-tables`](crates/sqlite-tables) | NodeQL-Lese-API für Tabellen, Views, Seitennavigation, Spalten, Schlüssel und Indizes. Nutzt die eingebettete SQLite-Engine für die konsistente Lesesicht und für Arbeitskopien aktiver Datenbanken mit WAL. |

NodeQL verwendet die zweite Crate für „DB laden“ und für den Tabellenbrowser.
Beide Crates sind lokale Cargo-Abhängigkeiten mit `publish = false`.

```rust
use nodeql_sqlite_tables::Reader;
use std::{path::Path, sync::{Arc, atomic::AtomicBool}};

let mut db = Reader::open(Path::new("beispiel.db"))?;
let schema = db.tables()?;
let page = db.table("kunden", 0, 25, Arc::new(AtomicBool::new(false)))?;
```

Für die direkte Dateianalyse liest `Image::open` eine stabile Kopie, etwa aus
`Reader::snapshot`. `Image::schema` liefert die gespeicherten Schemaeinträge und
`Image::visit_table` liefert die Datensätze einzeln. Diese API liefert die
physische Feldreihenfolge, den Rowid separat und die gespeicherten Werte.
SQL-Views, virtuelle Tabellen sowie SQL-Standardwerte werden über `Reader`
ausgewertet. Bei einem nicht leeren WAL oder Rollback-Journal benötigt `Image`
eine konsistente Arbeitskopie.

## Tests und Build

```sh
cargo fmt --check
cargo test --workspace --locked
cargo clippy --workspace --locked --all-targets -- -D warnings
cargo build --workspace --locked --release
```

Der Kern lässt sich auch ohne Desktop-/Grafikabhängigkeiten prüfen:

```sh
cargo test --locked --no-default-features
cargo run --locked --no-default-features --example smoke
```

## Aufbau

| Modul | Verantwortung |
| --- | --- |
| `src/model.rs` | Typisierte Blöcke, Projektmodell, stabile Block-IDs |
| `src/compiler.rs` | Abfolge validieren, SQL erzeugen, Blockdiagnosen |
| `src/database.rs` | SQLite-Ausführung, Rollback, Laufzeitlimits und Anbindung der Lese-API |
| `src/project.rs` | Formatvalidierung und atomische JSON-Persistenz |
| `src/export.rs` | CSV, TSV und typisierter JSON-Export |
| `src/flutter_project.rs` | Import unterstützter Flutter-Projekte |
| `src/sql_import.rs` | SQL-Text in editierbare Blöcke umwandeln |
| `src/app.rs` | egui-Oberfläche und Anbindung des Datenbank-Threads |
| `assets/demo.sql` | Lokale Beispieldaten ohne Netzwerkzugriff |
| `tests/core.rs` | Integrationstests für Compiler, SQLite und Persistenz |

## Projektformat

Rust-Projekte verwenden `format: "nodeql_rust_project"`, `version: 1` und die
Dateiendung `.nodeql-rust.json`. Sie speichern Name, Datenbankpfad und Ablauf.
`database: null` steht für die eingebaute Demo-Datenbank; deren Daten werden
nicht im Projekt gespeichert. Die Oberfläche speichert absolute Datenbankpfade;
relative Pfade in Projektdateien werden relativ zum Projektordner aufgelöst.

„Projekt öffnen“ importiert auch unterstützte Flutter-Dateien
(`nodeql_project_v2`, `scratchql_project_v2` und ältere Workspace-Dateien).
Der Import übernimmt Query-Tabs, Datenbankreferenzen, verbundene SQL-Blöcke und
einzelne lose Blöcke. Unterstützte verschachtelte Reporter werden als editierbare
SQL-Ausdrücke übernommen. Der Import meldet unbekannte Blöcke und Ketten. Das
erste Speichern legt eine Rust-Projektdatei an. Der Rückexport in das Flutter-
Format steht aus.

## Weitere Migration

Dies ist ein funktionaler erster Ausschnitt, noch kein vollständiger Ersatz.
Die Reihenfolge für den weiteren Port ist in [MIGRATION.md](MIGRATION.md) erfasst.

Technische Grundlagen: [eframe](https://docs.rs/eframe/0.37.0/eframe/),
[egui](https://docs.rs/egui/0.37.0/egui/),
[rusqlite](https://docs.rs/rusqlite/0.41.1/rusqlite/),
[native Dateidialoge](https://docs.rs/rfd/0.17.2/rfd/).
