# Migrationsstand

Ziel: NodeQL vollständig als native Rust-Anwendung weiterentwickeln, mit
plattformübergreifendem Desktop-Frontend und einem von der Oberfläche getrennten
Rust-Kern. Der Flutter-Bestand dient als fachliche Referenz.

## 1. Lauffähiger vertikaler Ausschnitt — umgesetzt

Projekt → Blockablauf → SQL → lokale SQLite-Datenbank → Ergebnistabelle → Export.
Native Fenster und Dateidialoge, Datei-Persistenz sowie Tests gehören dazu.
Die Rust-Oberfläche bietet Deutsch und Englisch.

## 2. Visuelles Blockmodell und Editor

Die Rust-Workbench verwendet jetzt Layout, Blockformen und Assets der
Flutter-Referenz. Query-Tabs, frei platzierbare Blöcke, Andocken, Zoom, Pan und
Undo/Redo sowie die Auswahl von Tabellen und Spalten sind verfügbar. Dazu
kommen verschachtelte Reporter, Funktions- und Alias-Reporter, mehrere
Startketten, ein gespeicherter Viewport pro Tab und die Navigation vom SQL zum
erzeugenden Block. Weitere Flutter-Blockvarianten und vollständige
Tastaturbedienung stehen noch aus.

Referenz: `lib/engine/block/`,
`lib/features/workbench/presentation/engine/workspace_engine.dart`,
`lib/features/workbench/presentation/engine/sql_compiler.dart`.

## 3. Projektkompatibilität

Der Import für unterstützte `nodeql_project_v2`-Dateien übernimmt Query-Tabs,
Blockpositionen, Startketten, relative Datenbankpfade, Autosave-Einstellungen
und unterstützte Reporter. Die Quelldatei bleibt erhalten. Autosave,
Wiederherstellung und zuletzt geöffnete Projekte sind in Rust vorhanden.
Weitere Blockvarianten, Altformat-Sonderfälle und Rückexport nach Flutter
stehen aus.

Referenz: `_projectEnvelope()` in
`lib/features/workbench/presentation/workbench_page.dart`,
`lib/data/project/project_file_upgrade_service.dart`,
`lib/features/workbench/presentation/engine/workspace_tabs.dart`.

## 4. SQL-Funktionsumfang

Schreibende Blöcke für Daten und Schema, grafische Tabellenerstellung, manuelle
SQL-Skripte mit Rollback und Export als CSV, JSON und TSV sind verfügbar. Der
SQL-Editor wandelt unterstützte SELECT-, Daten- und Schema-Anweisungen in neue
Query-Tabs um. Unterabfragen sind als SQL-Ausdruck möglich und Mengenoperationen
als Blöcke. CTEs und Transaktionsblöcke sind verfügbar. Transaktionsgruppen
werden über Savepoints innerhalb eines atomaren Programmlaufs ausgeführt.
ATTACH, DETACH und VACUUM werden einzeln ausgeführt. Die eigenen Rust-Crates
lesen SQLite-Dateien und liefern Tabellenmetadaten sowie SQLite-Seiten für den
Tabellenbrowser. Export der vollständigen Ergebnisse oberhalb des
Vorschau-Limits und Ausführungsverlauf stehen aus.

## 5. Produktfunktionen und Auslieferung

- Interaktive gebündelte Lernpfade mit separater Datenbank und gespeicherten
  Fortschritten sind verfügbar. Weitere Flutter-Workshop-Abläufe stehen aus.
- Lokalisierung mit englischem Fallback, allen vorhandenen Sprachen und RTL.
- Barrierefreiheit einschließlich Screenreader und reiner Tastaturbedienung.
- Einstellungen, plattformspezifische Installation und Update-Verfahren.
- CI und echte Builds auf macOS, Windows und Linux; Plattformpakete und
  Signierung getrennt vom Flutter-Releaseprozess einrichten.

Die vorhandenen Flutter-Releases und deren Versions-/Buildnummern bleiben ein
separater Auslieferungsweg. Der neue Rust-Stand ist noch keine veröffentlichte
Release und wurde nicht als funktionsgleich zertifiziert.
