# Visueller Abgleich mit NodeQL Flutter

final result: passed

Der Abgleich umfasst die Workbench und die Datenansicht des Tabellenbrowsers auf macOS. Beide Builds wurden bei gleicher Fenstergröße (3420 × 1996 Gerätepixel), im dunklen Farbschema, auf Deutsch und im Einfach-Modus verglichen. Grundlage waren der laufende Flutter-Demo-Build und die Referenzbilder `NodeQLApp.png`, `NodeQLAppWhite.png` und `NodeQLTableBrowser.png` unter `docs/screenshots/`.

| Ansicht | Verglichene Details | Verbleibende Unterschiede |
| --- | --- | --- |
| Workbench | Toolbar, Kategorieleiste, Suchpalette, Query-Tabs, Blockformen, SQL- und Ausgabe-Panels. Beide Fenster zeigten dieselbe SELECT-, JOIN- und ORDER-BY-Kette. | Schrift- und Kantenglättung, Details der Verbindungslinien und Scrollleisten. |
| Tabellenbrowser | Kopfzeile mit Kennzahlen, Tabellenleiste, Daten- und Spalten-Tabs, SQLite-Zeilen und Seitennavigation. In beiden Builds war `Categories` ausgewählt. | Rust verwendet eine lokale Demo mit derselben Tabellenstruktur. Der inzwischen ergänzte Tabelleneditor gehört nicht zu diesem visuellen Abgleich. |

Beim Abgleich wurden die Flächenfarben, die Abstände der Suchpalette, die Größen der Blockfelder und die Systemschrift nachgezogen. Der native Wechsel in den Erweitert-Modus wurde separat geprüft. Ein automatisierter Oberflächentest prüft das Andocken und Lösen eines Filterblocks, dessen SQLite-Ergebnis und das erneute Öffnen der gespeicherten Projektdatei.

Das Ergebnis gilt für die verglichenen Ansichten. Der aktuelle Funktionsstand und die Abweichungen zur Flutter-Version sind im Migrationsstand erfasst.

Im aktuellen macOS-Bundle wurde der Einfach-Modus des Tabelleneditors zusätzlich funktional geprüft. Eine Testtabelle wurde in der flüchtigen Demo angelegt und anschließend im Tabellenbrowser mit der Spalte `id` angezeigt.
