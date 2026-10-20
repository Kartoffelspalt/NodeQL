# Workshop-Tutorials erstellen

## Im separaten Admin-Build

Das **Learning Path Studio** ist ausschließlich im privaten Desktop-Projekt
`tools/workshop_admin` verfügbar. Der reguläre NodeQL-Build zeigt nur
veröffentlichte Workshops an und enthält weder den Studio-Startpunkt noch den
Datei-Import/-Export. Start und Build des Admin-Werkzeugs sind in
`docs/admin-workshop-build.md` beschrieben.

Im Admin-Workshop öffnet der Button **Workshop Studio** das Authoring-Werkzeug.
Der empfohlene Ablauf ist:

1. Die Nodes für den ersten Schritt auf der Workshop-Arbeitsfläche bauen und
   vollständig konfigurieren.
2. Das Learning Path Studio öffnen, einen Pfad anlegen und **Aktuelle Nodes als
   Schritt übernehmen** wählen.
3. Titel, Aufgabe und optionalen Hinweis für den Schritt eintragen.
4. Für jede Erklärung einen Ziel-Node, links oder rechts, einen Titel und den
   Erklärungstext auswählen. Die Beschriftung erscheint beim Abspielen als
   nummerierte Timeline-Karte außerhalb des Nodes.
5. Den Pfad speichern. Für weitere Schritte die Arbeitsfläche anpassen, das
   Studio erneut öffnen, den Pfad bearbeiten und den nächsten Snapshot
   hinzufügen.

Eigene Learning Paths werden lokal in `nodeql_learning_paths.json` im
Application-Support-Verzeichnis des Admin-Builds gespeichert. **Start** öffnet
den Pfad im geführten Player. Dieser zeigt die Schritt-Timeline oberhalb der
Arbeitsfläche und verankert Beschriftungen an den aufgebauten Nodes.
**Publish bundle** exportiert die veröffentlichbare `workshops.json`.

## Deklarativ im Quellcode

Die offiziellen Workshops stammen aus `assets/workshops/workshops.json`.
Ihre Übersicht und ihr Fortschritt verwenden stabile Workshop- und Schritt-IDs;
die reguläre App zeigt ausschließlich diese veröffentlichten Pfade.

Die älteren Tutorial-APIs in `lib/features/tutorial/tutorial_practice.dart`
bleiben für Kompatibilität erhalten, sind aber nicht die Quelle des offiziellen
Curriculums. Der Legacy-Katalog enthält nur noch die beiden Theorie-Module
und wird bei einem leeren Bundle als Fallback verwendet.

Für neue Dateien kann die kleine Authoring-API importiert werden:

```dart
import 'package:nodeql/features/tutorial/tutorial_framework.dart';
```

## Ein neues Praxistutorial

1. Einen Wert zu `TutorialKnowledgeMode` in
   `lib/features/tutorial/tutorial_models.dart` ergänzen. SQLite-Übungen
   erhalten automatisch den SQLite-Bereich; NodeQL-Theorie wird in der
   `area`-Extension explizit zugeordnet.
2. In `_practiceDefinitions` eine `TutorialPracticeDefinition` hinzufügen.
   Die Kennung ist optional; ohne sie wird stabil der Enum-Name verwendet.
3. Die zugehörigen Übersetzungen ergänzen. Eine Mission benötigt mindestens
   `title`, `instruction`, `hint`, `example` und `concept`.

```dart
TutorialKnowledgeMode.windowFunctions: TutorialPracticeDefinition(
  id: 'window-functions',
  mode: TutorialKnowledgeMode.windowFunctions,
  simpleStarter: [
    workshopNode(BlockType.sqlSelect, {
      'columns': 'name',
      'table': 'customers',
      'separate_from': false,
    }),
  ],
  advancedStarter: const [],
  steps: [
    workshopMission(
      id: 'add-ranking',
      checks: const [TutorialPracticeCheck.selectConnected],
      focusNodes: const [BlockType.sqlSelect],
      estimatedMinutes: 3,
    ),
  ],
),
```

`starterSeeds` startet eine Mission mit genau diesen Nodes. Ohne
`starterSeeds` wird der Basisstarter samt den `resumeSeeds` der vorherigen
Missionen verwendet. Mit `startFresh: true` beginnt die nächste Mission auf
einer leeren Arbeitsfläche.

## Prüfungen

`TutorialPracticeCheck` deckt die üblichen SQLite-Aufgaben ab, etwa
`selectConfigured`, `whereConfigured`, `joinConfigured`,
`queryExecuted` und `transactionOrderValid`. Mehrere Checks werden alle
sichtbar im Coach angezeigt und müssen erfüllt sein.

Für eine fachliche Spezialregel gibt es eine benannte, übersetzbare Prüfung:

```dart
TutorialPracticeRequirement.custom(
  id: 'runs-current-sql',
  labelKey: 'tutorial.practice.check.runsCurrentSql',
  validator: (graph, context) =>
      graph.statements.any((node) => node.type == BlockType.sqlSelect) &&
      context.currentSqlWasExecuted,
),
```

`graph` enthält alle verbundenen Statement-Nodes und Reporter; `context`
enthält die aktuell erzeugte SQL, die zuletzt ausgeführte SQL und den
Ausführungsstatus. Die Katalogvalidierung verhindert leere bzw. doppelte
Tutorial-IDs und doppelte Missions-IDs bereits beim Start.

## Übersetzungsschlüssel

Für `TutorialKnowledgeMode.windowFunctions` und die erste Mission werden
folgende Schlüssel verwendet:

```text
tutorial.mode.windowFunctions
tutorial.lesson.windowFunctions.description
tutorial.practice.windowFunctions.tab
tutorial.practice.windowFunctions.step.1.title
tutorial.practice.windowFunctions.step.1.instruction
tutorial.practice.windowFunctions.step.1.hint
tutorial.practice.windowFunctions.step.1.example
tutorial.practice.windowFunctions.step.1.concept
```

Neue Standardchecks verwenden automatisch
`tutorial.practice.check.<check-name>`. Für Custom-Checks wird `labelKey`
direkt verwendet. Mindestens die englische Übersetzung sollte ergänzt werden;
der Übersetzungskatalog fällt für weitere Sprachen darauf zurück.
