# NodeQL Workshop Admin

Der Workshop Admin ist eine eigenständige Flutter-Desktop-Anwendung unter
`tools/workshop_admin`. Sie besitzt eigene native Runner und die separate
App-ID `org.nodeql.nodeqlWorkshopAdmin`. Der öffentliche NodeQL-Release wird
weiterhin ausschließlich aus `lib/main.dart` gebaut.

## Starten und bauen

```bash
cd tools/workshop_admin
flutter pub get
flutter run -d macos
```

Für ein lokales macOS-Artefakt:

```bash
cd tools/workshop_admin
flutter build macos --release
```

Unter Windows beziehungsweise Linux wird entsprechend `flutter build windows
--release` oder `flutter build linux --release` verwendet.

## Builds und Release in GitHub Actions

Der Workflow **Workshop Admin** testet und baut die App bei relevanten
Änderungen auf `master` oder `main` und lässt sich auch manuell starten.
Unter **Artifacts** im Workflow-Lauf liegen die Pakete für Linux x64
(`.tar.gz`), macOS (`.zip`) und Windows x64 (`.zip`). Die macOS-App ist
ad hoc signiert. Unter Windows wird das
[Microsoft Visual C++ Redistributable für x64](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/)
benötigt, falls es auf dem Rechner noch fehlt.

Für einen separaten Release die Version in `tools/workshop_admin/pubspec.yaml`
pflegen und **Actions → Workshop Admin → Run workflow** auf `master` mit
`create_release_draft` starten. Der Workflow legt nach erfolgreichen Builds
einen Entwurf mit den drei Paketen, `SHA256SUMS.txt` und einem eigenen Tag
wie `workshop-admin-v1.0.0+1` an. Bei der Veröffentlichung die Markierung
als Pre-Release beibehalten, damit der Update-Feed von NodeQL auf dem
regulären Release bleibt.

## Einen Workshop erstellen

1. **Workshop Admin** öffnen. Die Arbeitsfläche mit Palette und Nodes ist
   direkt bedienbar. Rechts ersetzen die Erstellungswerkzeuge die SQLite-
   und Output-Vorschau. **Neuer Workshop** wählen und einen Namen eingeben.
2. **Schritt hinzufügen** wählen, einen Titel und die Aufgabe für die Klasse
   schreiben. Der Schritt wird direkt im rechten Bereich bearbeitet.
3. Nodes auf der Arbeitsfläche vorbereiten und bei Bedarf **Aktuelle Nodes
   übernehmen** wählen. Unter **Übungs-Nodes** die Auswahl anpassen und
   unter **Interaktion** Markierungen und Prüfungen ergänzen. Auch die
   Eingabeprüfung öffnet sich direkt im rechten Bereich.
4. **Schritt übernehmen** und **Speichern** wählen. **Speichern und
   ausprobieren** startet den Player am ersten Schritt und zeigt beide
   Vorschauen. Mit **Weiter bearbeiten** werden die Werkzeuge und der
   Node-Aufbau vor dem Test wiederhergestellt.

Eigene gespeicherte Workshops stehen oben im Studio.

Beispiel für den Einstieg ist ein Workshop mit dem Namen *Kunden nach Stadt
filtern*. Der erste Schritt kann *Kunden anzeigen* heißen und die Aufgabe
*Zeige alle Kunden aus Berlin* enthalten. Eine Textaufgabe genügt für den
ersten Entwurf.

### Einen interaktiven Schritt bauen

1. Die benötigten Nodes auf der Arbeitsfläche vorbereiten. Im Schritt unter
   **Übungs-Nodes** auswählen, welche Nodes die Klasse einsetzen soll.
   Eingebettete Wert-Nodes erscheinen als eigene Übungs-Nodes.
2. Unter **Interaktion** die Nodes markieren, die hervorgehoben werden sollen.
   Unter **Node-Beschriftungen** lassen sich Erklärungen direkt am Node anzeigen.
3. Mit **Prüfung hinzufügen** festlegen, worauf der Player wartet. Zum Beispiel
   **Wert eingeben** wählen, als Ziel den SELECT-Node, als Feld **Tabelle**
   und optional `customers` als erwarteten Wert eintragen.
4. Mit **Speichern und ausprobieren** prüfen, ob die Aktion **Weiter** freigibt.
   Ein vorbelegter Wert zählt erst, nachdem die Lernenden das Feld im
   betreffenden Schritt bestätigt haben.

Der Player kann außerdem auf die Auswahl eines Nodes, das Andocken zweier
Nodes, einen Wert-Node im vorgesehenen Feld, eine Spaltenverbindung oder die
erfolgreiche Ausführung der aktuellen Abfrage warten. Er markiert die jeweils
relevanten Nodes, Felder und Werkzeuge. Eine Prüfung greift, sobald die
beteiligten Nodes an der Reihe sind. Die Ausführungsprüfung greift am Ende
des Schritts und prüft, ob die aktuell erzeugte Abfrage erfolgreich
ausgeführt wurde.

Bundles mit diesen Prüfungen verwenden Format 2 und benötigen eine
Desktop-App mit Unterstützung für interaktive Schritte.

## Den offiziellen Katalog veröffentlichen

Mit **Katalog exportieren** eine Datei namens `workshops.json` speichern.
Die geprüfte Datei als `assets/workshops/workshops.json` in das Hauptprojekt
übernehmen und normal testen.

Die reguläre Anwendung lädt dieses versionierte Bundle beim Start des
Workshop-Bereichs. Die Einträge erscheinen dort als offizielle **NodeQL Workshops**
mit Timeline, Node-Beschriftungen und Fortschrittsanzeige. Pro Workshop werden
abgeschlossene Schritt-IDs, der aktuelle Node, Simple-/Advanced-Modus und die
Arbeitsfläche in `nodeql_tutorial.json` gespeichert. **Fortsetzen** stellt diese
Arbeitsfläche wieder her; abgeschlossene Workshops können wiederholt werden.
Beim Wechsel zum nächsten Schritt bleiben die aufgebauten Nodes erhalten. Zum
Veröffentlichen ist ausschließlich das JSON-Bundle nötig; der Admin-Build wird
nicht verteilt.

## Einen Workshop im Unterricht teilen

1. Lehrkraft und Klasse verbinden ihre Rechner mit demselben lokalen Netz.
2. Die Lehrkraft wählt im **Workshop Studio** am gewünschten Workshop
   **Im Unterricht teilen → Code erstellen → Code kopieren**. Falls
   mehrere Netzwerke verfügbar sind, lässt sich die vorausgewählte Verbindung
   unter **Netzwerk wechseln** anpassen.
3. Die Lernenden wählen in NodeQL **Workshop → Code eingeben → Einfügen**.
   Nach der Vorschau öffnet **Speichern und starten** den Workshop direkt.
4. Die Lehrkraft lässt die Freigabe geöffnet, bis die Klasse beigetreten ist.
   Mit **Freigabe beenden**, beim Schließen des Freigabebereichs oder spätestens nach
   30 Minuten endet die Freigabe. Installierte Workshops sind weiter offline
   spielbar.

Falls sich die Geräte im lokalen Netz nicht erreichen, wählt die Lehrkraft
im selben Freigabebereich **Datei speichern** und verteilt die JSON-Datei
über den üblichen Unterrichtskanal oder per Datenträger. Die Klasse wählt
**Workshop → Code eingeben → Datei öffnen**.
Der Import prüft die Datei vor der Installation nach denselben Inhaltsregeln.

Die Freigabe bindet sich an die ausgewählte private IPv4-Adresse.
Der Unterrichtscode enthält einen zufälligen Schlüssel und die
SHA-256-Prüfsumme der freigegebenen Fassung. Das Workshop-Bundle wird direkt
zwischen den Geräten mit AES-GCM verschlüsselt übertragen. Wer den Code hat,
kann das Bundle während der Freigabe abrufen. Der Code gehört deshalb in den
Klassenkanal. NodeQL braucht für die Freigabe keine Konten und speichert
Lernfortschritt lokal auf dem jeweiligen Gerät. [Dart-Bibliothek für AES-GCM](https://pub.dev/documentation/cryptography/latest/cryptography/AesGcm-class.html)

Auf macOS kann NodeQL beim Beitritt um Zugriff auf das lokale Netz bitten.
[Apple-Dokumentation zur Berechtigung](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## Einen eigenen Workshop als Download teilen

1. Einen Learning Path im Studio anlegen und testen. Am gewünschten Eintrag
   **Für Download exportieren** wählen. Der Export prüft das Download-Format
   und speichert genau einen Workshop als JSON.
2. Die unveränderte Datei öffentlich auf GitHub Pages oder unter
   `raw.githubusercontent.com` bereitstellen. Die direkte HTTPS-Adresse
   muss auf `.json` enden und ohne Weiterleitung oder Query-Parameter
   erreichbar sein.
3. Die SHA-256-Prüfsumme der veröffentlichten Bytes ermitteln, zum Beispiel
   mit `shasum -a 256 mein-workshop.json`. Die 64 kleinen Hex-Zeichen mit
   `#sha256=` an die Adresse anhängen und den vollständigen Link teilen.

```text
https://<konto>.github.io/<repo>/mein-workshop.json#sha256=<64-hex-zeichen>
```

In der Desktop-App lässt sich der Link unter **Workshop → Code eingeben →
GitHub-Link** prüfen. Nach der Vorschau und Bestätigung ist der Workshop
offline spielbar. Die Prüfsumme bindet den Link an eine konkrete Fassung.
Die Vertrauensentscheidung über den Herausgeber erfolgt beim Erhalt des
Links. Für eine neue Fassung einen neuen Link teilen. Jede Fassung hat einen
eigenen Fortschritt und kann separat entfernt werden.

Für Downloads gelten maximal 256 KiB pro Bundle, 32 Schritte pro Workshop und
16 Nodes sowie 16 Beschriftungen pro Schritt. Die App speichert bis zu
20 Downloads. Unterstützt werden SELECT, FROM, Spalten, typisierte Literale,
Filter, JOIN, GROUP BY, COUNT, SUM, AVG, MIN, MAX, ORDER BY und LIMIT.
Nodes dürfen einfache strukturierte Standardwerte wie Spaltennamen,
Vergleichsoperatoren und Literale enthalten. Reporter für den geführten
Einbau als eigene Nodes erfassen. Ein Download akzeptiert weder eingebettete
Reporter-Bäume noch freie SQL-Snippets. Die Ausführung ist auf eine einzelne
SELECT-Abfrage mit bis zu drei JOINs auf frisch erzeugten Übungsdaten im
Arbeitsspeicher beschränkt.

## Technische Trennung

- `tools/workshop_admin` enthält Entry Point, Datei-Picker und Studio-Bereich.
- Die normale App kennt nur den standardmäßig leeren Provider
  `workshopAdminActionProvider` und `workshopAdminPanelProvider`.
- Die reguläre Learning-Path-Bibliothek lädt das veröffentlichte Asset-Bundle
  schreibgeschützt. Geprüfte Downloads stehen in einem getrennten Bereich.
- Nur das Admin-Projekt überschreibt diesen Provider und importiert
  `learning_path_studio.dart`; zusätzlich aktiviert es die lokale,
  schreibbare Entwurfsbibliothek.
- `.github/workflows/release.yml` baut explizit `lib/main.dart`.
- Der Boundary-Test verhindert, dass Admin-Imports oder der Admin-Projektpfad
  in den öffentlichen Release-Graph beziehungsweise Workflow gelangen.

Lokal gespeicherte Entwürfe und das veröffentlichte Bundle sind getrennt. Das
verhindert, dass ein unfertiger Workshop allein durch Speichern im Admin-Tool
in einer Release-Version erscheint.

## PDF-Materialien

- [Workshops erstellen](../output/pdf/NodeQL-Workshops-erstellen.pdf) erklärt
  auf 19 Seiten den eingebetteten Editor mit Screenshots, allen Prüfungsarten,
  einem vollständigen Beispielworkshop, Freigabe und Fehlersuche.
- [Unterrichtsmaterial](../output/pdf/NodeQL-Unterrichtsmaterial.pdf) bietet
  27 Seiten im Projektionsformat mit Aufgaben, Arbeitsblättern und geprüften
  Lösungen auf den eingebauten Übungsdaten. Ein Ablauf für zwei Schulstunden
  und eine gekürzte Variante für 45 Minuten sind im Leitfaden beschrieben.
  Alle Personen in den Übungsdaten tragen traditionelle deutsche Vornamen.
