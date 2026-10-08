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
--release` oder `flutter build linux --release` verwendet. Diese Builds sind
rein lokal. Der Release-Workflow im Repository wechselt nie in das
`tools/workshop_admin`-Projekt und lädt daher kein Admin-Artefakt hoch.

## Einen Workshop veröffentlichen

1. Im Admin-Build den Workshop-Modus öffnen.
2. Die Nodes für einen Schritt aufbauen und vollständig konfigurieren.
3. **Workshop Studio** öffnen und einen Learning Path anlegen.
4. **Aktuelle Nodes als Schritt übernehmen** verwenden und Titel, Aufgabe,
   Hinweis sowie die externen Node-Beschriftungen ergänzen.
5. Mit **Start** den Pfad im echten Workshop-Player prüfen.
6. Mit **Publish bundle** eine Datei namens `workshops.json` exportieren.
7. Die geprüfte Datei als `assets/workshops/workshops.json` in das Hauptprojekt
   übernehmen und normal testen.

Die reguläre Anwendung lädt dieses versionierte Bundle beim Start des
Workshop-Bereichs. Die Einträge erscheinen dort unter **Published workshops**
und können inklusive Timeline und Node-Beschriftungen abgespielt werden. Zum
Veröffentlichen ist ausschließlich das JSON-Bundle nötig; der Admin-Build wird
nicht verteilt.

## Technische Trennung

- `tools/workshop_admin` enthält Entry Point, Datei-Picker und Studio-Launcher.
- Die normale App kennt nur den standardmäßig leeren Provider
  `workshopAdminActionProvider`.
- Ihre Learning-Path-Bibliothek ist read-only und lädt ausschließlich das
  veröffentlichte Asset-Bundle.
- Nur das Admin-Projekt überschreibt diesen Provider und importiert
  `learning_path_studio.dart`; zusätzlich aktiviert es die lokale,
  schreibbare Entwurfsbibliothek.
- `.github/workflows/release.yml` baut explizit `lib/main.dart`.
- Der Boundary-Test verhindert, dass Admin-Imports oder der Admin-Projektpfad
  in den öffentlichen Release-Graph beziehungsweise Workflow gelangen.

Lokal gespeicherte Entwürfe und das veröffentlichte Bundle sind getrennt. Das
verhindert, dass ein unfertiger Workshop allein durch Speichern im Admin-Tool
in einer Release-Version erscheint.
