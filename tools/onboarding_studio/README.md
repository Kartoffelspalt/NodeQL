# NodeQL Onboarding Studio

Ein privates Entwicklungswerkzeug zum Erstellen von UI-Walkthroughs, ähnlich
dem Onboarding-Editor von FlutterFlow. Das Tool ist eigenständig und gehört
bewusst nicht zum NodeQL-Release: Es wird weder vom Root-`pubspec.yaml` noch
von einer Produkt-Build-Konfiguration referenziert.

## Starten

```bash
cd tools/onboarding_studio
flutter pub get
flutter run -d macos
```

Native Runner für macOS, Windows und Linux sind im Tool-Projekt enthalten.
Je nach Betriebssystem kann zum Beispiel `flutter run -d windows` oder
`flutter run -d linux` verwendet werden. Die Web-Ausführung bleibt nur eine
optionale schnelle Vorschau.

## Bedienung

1. Links einen Schritt auswählen, hinzufügen oder sortieren.
2. Rechts Zielbereich, Titel, Erklärung und Tooltip-Position bearbeiten.
3. In der Mitte den Entwurf oder mit **Vorschau abspielen** die spätere
   Anleitung prüfen.
4. Über **JSON kopieren** oder **JSON exportieren** die Konfiguration für die
   spätere Produktintegration ausgeben.

## In NodeQL testen

Nach dem Export kann die Datei direkt in NodeQL getestet werden: In der
Toolbar öffnet das Datei-Icon neben dem Hilfe-Icon den Import. NodeQL prüft
das JSON und hebt dann die realen Zielbereiche der Anwendung hervor. Der
Hilfe-Button startet weiterhin die eingebaute Beispiel-Anleitung.

Die Beispielvorlage erklärt vier zentrale Teile der NodeQL-Oberfläche:
**Node-Leiste**, **Node-Arbeitsfläche**, **Datenbank-Tools** und **Workshop**.
Die Ausgabe nutzt dafür stabile semantische Ziel-IDs (`nodePalette`,
`workspace`, `databaseTools`, `workshop`). Eine Laufzeit-Integration kann
diese IDs gezielt auf `GlobalKey`-Widgets in NodeQL abbilden, ohne dieses Tool
in die Produkt-App übernehmen zu müssen.
