# NodeQL Wiki

Dieses Wiki erklaert vor allem, wie NodeQL funktioniert: von der sichtbaren
Arbeitsflaeche ueber die internen Blockdaten bis zur SQL-Ausfuehrung gegen eine
lokale SQLite-Datenbank.

## Kurzfassung

NodeQL ist eine local-first Desktop-Anwendung zum Lernen, Entwerfen und
Ausfuehren von SQL mit visuellen Bloecken. Der Nutzer arbeitet nicht direkt in
einem Texteditor, sondern setzt SQL-Bausteine grafisch zusammen. NodeQL
uebersetzt diese Blockstruktur in SQL, zeigt die Abfrage an und fuehrt sie auf
Wunsch gegen eine lokale SQLite-Datenbank aus.

Der wichtigste Ablauf ist:

```text
Block-Palette -> Workspace -> Blockbaum -> SQL-Compiler -> SQL-Vorschau
              -> SQLite-Runtime -> Ergebnis-Tabelle / Meldung
```

Projekte, Einstellungen, installierte Plugins und Datenbanken bleiben auf dem
Geraet. NodeQL ist kein Cloud-Dienst und kein Machine-Learning-Projekt.

## Was man in NodeQL sieht

Die zentrale Oberflaeche ist die Workbench. Sie besteht aus mehreren Bereichen:

| Bereich | Funktion |
| --- | --- |
| Block-Palette | Enthaltene SQL-, Kontroll-, Operator- und Plugin-Bloecke |
| Workspace | Flaeche, auf der Bloecke platziert, verbunden und bearbeitet werden |
| SQL-Vorschau | Zeigt die aus den Bloecken generierte SQL-Anweisung |
| Datenbankbereich | Verbindet oder erstellt lokale SQLite-Datenbanken |
| Ergebnisbereich | Zeigt Ausfuehrungsmeldungen und Tabellenzeilen |
| Einstellungen | Sprache, Theme, Plugins, Repositories und weitere App-Optionen |

Die Workbench ist bewusst wie ein visueller SQL-Baukasten aufgebaut. Ein Nutzer
sieht also nicht nur das Endergebnis, sondern auch die Struktur der Abfrage.

## Das Grundprinzip der Bloecke

Jeder Block ist intern ein `BlockNode`. Ein Block speichert:

- eine eindeutige `id`
- einen `type`, zum Beispiel `sqlSelect`, `sqlWhere` oder `sqlJoin`
- eine `position` im Workspace
- optionale Eingaben in `inputs`
- einen naechsten Block in `next`
- verschachtelte Kinder in `children`

Damit kann NodeQL sowohl einfache lineare Abfragen als auch verschachtelte
Strukturen abbilden. Eine typische Kette sieht konzeptionell so aus:

```text
EXECUTE QUERY
  -> SELECT [columns]
  -> FROM [table]
  -> WHERE [predicate]
  -> ORDER BY [column]
```

Der Startblock `eventGreenFlag` ist der ausfuehrbare Einstiegspunkt. Bloecke,
die frei im Workspace liegen und nicht unter einem solchen Startblock haengen,
werden vom SQL-Compiler nicht als ausfuehrbare Abfrage behandelt.

## Wie aus Bloecken SQL wird

Die SQL-Erzeugung passiert im `SqlCompiler`. Er bekommt die Root-Bloecke des
Workspaces und laeuft die ausfuehrbaren Blockketten durch.

Der Compiler arbeitet vereinfacht in diesen Schritten:

1. Root-Bloecke suchen.
2. Nur Ketten unter `EXECUTE QUERY` kompilieren.
3. Jeden Blocktyp in ein SQL-Fragment uebersetzen.
4. `next`-Bloecke anhaengen.
5. `children` aus Container- oder Reporter-Bloecken einsetzen.
6. Plugin-Bloecke ueber ihr SQL-Template rendern.
7. Warnungen sammeln, wenn etwas nicht ausfuehrbar ist.
8. Am Ende pro Abfrage ein Semikolon ergaenzen.

Beispiele fuer eingebaute Blockuebersetzungen:

| Blocktyp | SQL-Fragment |
| --- | --- |
| `sqlSelect` | `SELECT ...` |
| `sqlFrom` | `FROM table_name` |
| `sqlWhere` | `WHERE predicate` |
| `sqlJoin` | `JOIN table ON condition` |
| `sqlGroupBy` | `GROUP BY column` |
| `sqlOrderBy` | `ORDER BY column direction` |
| `sqlCount` | `COUNT(column)` |
| `sqlInsert` | `INSERT INTO ...` |
| `sqlUpdate` | `UPDATE ... SET ...` |
| `sqlDelete` | `DELETE FROM ...` |

Das Ergebnis ist normale SQL-Syntax. NodeQL versteckt SQL also nicht, sondern
macht sichtbar, wie die visuelle Struktur in echten SQL-Text uebersetzt wird.

## Warum es einen EXECUTE-QUERY-Startblock gibt

NodeQL unterscheidet zwischen Bloecken, die nur im Workspace liegen, und
Bloecken, die wirklich ausgefuehrt werden sollen. Der Startblock markiert diese
Grenze.

Das hat drei Vorteile:

- Nutzer koennen Bloecke vorbereiten, ohne sie sofort auszufuehren.
- Mehrere Abfrageketten koennen in einem Projekt existieren.
- Der Compiler kann klar entscheiden, welche Kette SQL erzeugen soll.

Liegt ein SQL-Block frei im Workspace, erzeugt NodeQL eine Warnung statt ihn
stillschweigend auszufuehren.

## Slots, Inputs und Reporter

Viele Bloecke haben editierbare Slots. Ein Slot ist ein sichtbares Eingabefeld,
das intern in `inputs` gespeichert wird. Beispiele:

```text
SELECT [columns]
FROM [table]
WHERE [left] [operator] [right]
```

Reporter-Bloecke liefern Werte fuer andere Bloecke. Ein Aggregatblock wie
`COUNT(column)` kann zum Beispiel in einen SELECT-Slot eingesetzt werden. Dadurch
entsteht eine Struktur, die naeher an SQL-Ausdruecken liegt als reine Textfelder.

## Workspace und Snapping

Der Workspace verwaltet, wo Bloecke liegen und wie sie verbunden sind. Beim
Ziehen eines Blocks prueft NodeQL passende Andockpunkte. Wenn ein Block nahe
genug an einer erlaubten Stelle liegt, wird er angedockt.

Dabei entstehen zwei wichtige Beziehungen:

- `next`: Der Block kommt nach einem anderen Block in derselben Kette.
- `children`: Der Block liegt innerhalb eines Container-Blocks oder wird als
  eingebetteter Ausdruck verwendet.

Das Snapping ist nicht nur optisch. Es bestimmt die echte Datenstruktur, die
spaeter vom Compiler gelesen wird.

## SQL-Vorschau

Die SQL-Vorschau ist ein Kernbestandteil von NodeQL. Sie zeigt direkt, welche
SQL-Anweisung aus der aktuellen Blockstruktur entsteht.

Damit erfuellt sie drei Aufgaben:

- Lernhilfe: Nutzer sehen, welche SQL-Syntax zu welchem Block gehoert.
- Kontrolle: Fehler in Reihenfolge, Spaltennamen oder Bedingungen werden
  schneller sichtbar.
- Transparenz: Vor dem Ausfuehren ist klar, welche Abfrage an SQLite geht.

NodeQL ist dadurch kein Ersatz fuer SQL-Verstaendnis, sondern eine Oberflaeche,
die SQL-Struktur sichtbar und bearbeitbar macht.

## Lokale SQLite-Runtime

Die Ausfuehrung passiert in der `SqlRuntime`. Sie verwendet das Dart-Paket
`sqlite3` und ist deshalb nicht auf `/usr/bin/sqlite3` oder eine externe
System-CLI angewiesen.

Der Runtime-Ablauf:

1. Nutzer waehlt eine `.db`, `.sqlite` oder `.sqlite3` Datei aus.
2. NodeQL kopiert oder oeffnet die Datei in einem kontrollierten lokalen Pfad.
3. Die Runtime liest das Schema aus `sqlite_schema`.
4. Fuer jede Tabelle werden Spalten per `PRAGMA table_info(...)` ermittelt.
5. Beim Ausfuehren wird die aktuelle SQL-Anweisung an SQLite uebergeben.
6. Ergebniszeilen werden fuer die Vorschau begrenzt.
7. Statusmeldungen und Zeilen erscheinen im Ergebnisbereich.

Schreibende SQL-Anweisungen werden besonders behandelt. Vor potenziell
veraendernden Statements erstellt NodeQL einen Snapshot. Wenn die Ausfuehrung
fehlschlaegt, wird die Datenbank aus diesem Snapshot wiederhergestellt.

## Datenbank-Schema im UI

Nachdem eine Datenbank verbunden wurde, kennt NodeQL ihre Tabellen und Spalten.
Dieses Schema kann in der Oberflaeche verwendet werden, damit Nutzer passende
Tabellen- und Spaltennamen schneller finden.

NodeQL liest nur Nutzer-Tabellen:

```sql
SELECT name
FROM sqlite_schema
WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
ORDER BY name
```

Interne SQLite-Tabellen werden dadurch ausgeblendet.

## Projektdateien

Ein NodeQL-Projekt speichert die visuelle Arbeitsflaeche als JSON. Wichtig ist:
Nicht nur der erzeugte SQL-Text wird gespeichert, sondern die Blockstruktur.

Gespeichert werden unter anderem:

- Blocktypen
- Positionen
- Eingabewerte
- Verkettungen ueber `next`
- verschachtelte Bloecke ueber `children`
- Plugin-Referenzen

Dadurch kann ein Projekt spaeter wieder als visuelle Arbeitsflaeche geladen und
weiterbearbeitet werden.

## Plugin-System

Plugins erweitern NodeQL um neue Bloecke, ohne dass sie in die Flutter-App
kompiliert werden muessen. Ein Plugin ist ein deklaratives `plugin.json`
Manifest.

Ein Plugin-Block definiert unter anderem:

- eine stabile Plugin-ID
- Block-IDs
- Labels und Beschreibungen
- Form und Farbe
- Eingaben
- SQL-Templates
- optionale Mindestversion von NodeQL

Beim Kompilieren erkennt NodeQL, ob ein Block aus einem Plugin stammt. Dann wird
nicht ein fest eingebauter Dart-Case verwendet, sondern das SQL-Template des
Plugins gerendert.

Das ist der zentrale Unterschied:

```text
Built-in Block -> Dart switch/case im SqlCompiler
Plugin Block   -> Manifest + SQL-Template
```

## Plugin-Repositories

NodeQL kann Community-Plugin-Kataloge von statischen HTTPS-URLs installieren.
Das oeffentliche Beispiel-Repository ist:

```text
https://kartoffelspalt.github.io/nodeql-example-plugins/repository.catalog.json
```

Der Katalog verweist auf einzelne `plugin.json`-Manifeste. NodeQL prueft:

- ob der Katalog gueltig ist
- ob die Manifest-URL erreichbar ist
- ob der SHA-256-Hash zur Manifestdatei passt
- ob das Manifest dem Schema entspricht
- ob Plugin-ID und Version konsistent sind
- ob die NodeQL-Version kompatibel ist

Der SHA-256-Hash wird ueber die konkrete `plugin.json` berechnet, nicht ueber
den Plugin-Ordner.

## Data-Source-Plugins in SDK v2

SDK v2 erlaubt deklarative externe Datenquellen ueber feste JSON-over-HTTP
Adapter. Das bedeutet: NodeQL laedt weiterhin keinen fremden Code, kann aber
ueber klar definierte HTTP-Endpunkte mit Bridges sprechen.

Ein Data-Source-Plugin deklariert:

- erlaubte Netzwerkhosts
- benoetigte Secrets
- Schema-Endpunkt
- Query-Endpunkt
- feste Request- und Response-Struktur

So koennen zum Beispiel MongoDB-, Supabase-, REST- oder GraphQL-Bridges extern
gepflegt werden, waehrend NodeQL selbst nur den sicheren, festen Vertrag
ausfuehrt.

## Lokalisierung

Die sichtbaren Texte kommen aus ARB-Dateien unter `lib/l10n/` und werden nach
`lib/localization/generated/` generiert.

Unterstuetzte Sprachen:

- Deutsch
- Englisch
- Franzoesisch
- Spanisch
- Italienisch
- Portugiesisch
- Tuerkisch
- Arabisch mit RTL
- Japanisch
- Koreanisch
- Chinesisch

Nach Textaenderungen gilt:

```bash
flutter gen-l10n
```

Zur Laufzeit kann NodeQL ausserdem validierte Community-Sprachpakete verwenden.
Diese Pakete werden nach Schema, Groesse, Metadaten, Platzhaltern und Hashes
geprueft.

## Architektur im Code

Die wichtigsten Bereiche:

| Pfad | Aufgabe |
| --- | --- |
| `lib/core` | App-Bootstrap, Theme, Update-Pruefung |
| `lib/localization` | Sprache, Kataloge, Runtime-Uebersetzungen |
| `lib/domain` | Projekt- und Blockmodelle |
| `lib/data` | JSON-Persistenz und Standardprojekt |
| `lib/engine/block` | Blocktypen, Blockknoten, Syntax und Reporter |
| `lib/engine/plugins` | Plugin-Manifeste, Loader, Repository-Logik |
| `lib/engine/runtime` | Allgemeine Runtime-Modelle und Scheduler |
| `lib/engine/workspace` | Workspace-Modelle und Docking-Service |
| `lib/features/workbench` | Sichtbare Workbench, SQL-Modus, Compiler, Runtime |
| `lib/ui` | Shell und App-Einstieg |
| `test` | Unit-, Widget-, Runtime-, Plugin- und Workspace-Tests |

State Management basiert auf Riverpod. Routing erfolgt ueber `go_router`. Die
relevante Logik fuer Blockstruktur, SQL-Kompilierung, Plugin-Manifeste und
SQLite-Ausfuehrung ist testbar vom UI getrennt.

## Sicherheit und Datenschutz

NodeQL ist local-first. Das Design vermeidet unnoetige Netzwerkabhaengigkeiten.

Wichtige Sicherheitsgrenzen:

- Keine Analytics.
- Kein Account-Tracking.
- Kein automatisches Crash-Reporting.
- Lokale SQLite-Dateien bleiben lokal.
- Plugins fuehren keinen fremden Dart-, Native- oder Script-Code aus.
- Remote-Plugin-Repositories brauchen HTTPS.
- Manifeste werden mit SHA-256 und JSON-Schema validiert.
- Data-Source-Plugins muessen Hosts und Secrets deklarieren.

Optionales Netzwerkverhalten, zum Beispiel Update-Pruefungen, Plugin-Kataloge
oder Community-Uebersetzungen, ist gesondert dokumentiert.

## Typische Fehlerbilder

### Ein Block erzeugt kein SQL

Meist haengt er nicht unter einem `EXECUTE QUERY` Startblock oder er ist ein
Reporter, der nur als Eingabe fuer einen anderen Block gedacht ist.

### SQL sieht unvollstaendig aus

Pruefen, ob `SELECT`, `FROM`, `WHERE`, `JOIN` und weitere Klauseln in einer
sinnvollen Kette verbunden sind. Die visuelle Reihenfolge entspricht der
Kompilier-Reihenfolge.

### Datenbank ist verbunden, aber es erscheinen keine Tabellen

Die Runtime blendet interne SQLite-Tabellen aus. Wenn keine Nutzer-Tabellen
existieren, meldet NodeQL, dass die DB geladen wurde, aber keine User-Tabellen
gefunden wurden.

### Plugin-Installation schlaegt mit 404 fehl

Der Repository-Katalog ist oft erreichbar, aber `manifestUrl` zeigt auf eine
nicht existierende Datei. Pfad und Gross-/Kleinschreibung muessen exakt zur
GitHub-Pages-Struktur passen.

### SHA-256 stimmt nicht

Der Hash muss nach jeder Manifest-Aenderung neu ueber die referenzierte
`plugin.json` berechnet werden.

## Entwicklung und Tests

Wichtige Befehle:

```bash
flutter pub get
flutter gen-l10n
dart format lib test tool
flutter analyze
flutter test
dart run tool/validate_translations.dart
flutter run -d macos
```

Gezielte Tests:

```bash
flutter test test/plugins/plugin_manifest_test.dart
flutter test test/runtime/sql_runtime_test.dart
flutter test test/workspace/workspace_engine_test.dart
flutter test test/workspace/block_syntax_test.dart
```

Nach Aenderungen an Blocktypen, Compiler, Runtime oder Plugins sollten passende
Tests in den entsprechenden Subsystemen ergaenzt werden.

## Weiterfuehrende Dokumente

- `README.md` fuer die kurze Projektuebersicht.
- `docs/plugins/README.md` fuer Plugin SDK v1 und v2.
- `docs/localization/README.md` fuer Community-Uebersetzungen.
- `docs/RELEASING.md` fuer Release-Prozess und Signierung.
- `docs/node-ui-and-logic.md` fuer Hinweise zu Node-Aussehen und Logik.
- `CHANGELOG.md` fuer Aenderungshistorie.
- `PRIVACY.md` fuer Datenschutz.
- `SECURITY.md` fuer Sicherheitsmeldungen.
