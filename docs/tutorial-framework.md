# Workshop-Tutorials erstellen

## Im separaten Admin-Build

Das **Workshop Studio** ist ausschließlich im privaten Desktop-Projekt
`tools/workshop_admin` verfügbar. Im regulären NodeQL-Build stehen offizielle
Workshops und geprüfte Downloads zur Verfügung. Start, Build und
Veröffentlichung sind in [NodeQL Workshop Admin](admin-workshop-build.md)
beschrieben.

**Neuer Workshop** führt vom Namen zur ersten Aufgabe. Ein Schritt braucht
einen Titel und eine Aufgabe. Die Erstellungswerkzeuge liegen rechts neben
der bedienbaren Arbeitsfläche anstelle der beiden Vorschauen. In
**Übungs-Nodes** lässt sich pro Schritt auswählen, welche Nodes die Klasse
aufbaut. **Aktuelle Nodes übernehmen** aktualisiert die Auswahl direkt im
geöffneten Schritt. Beschriftungen lassen sich einzelnen Nodes zuordnen.

Unter **Interaktion** lässt sich pro Schritt festlegen, welche Nodes der
Player hervorhebt und welche Aktionen vor **Weiter** nötig sind. Das
Workshop-Admin-Handbuch enthält ein [Beispiel mit einer Eingabeprüfung](admin-workshop-build.md#einen-interaktiven-schritt-bauen).

Eigene Learning Paths werden lokal in `nodeql_learning_paths.json` im
Application-Support-Verzeichnis des Admin-Builds gespeichert.
**Speichern und ausprobieren** öffnet den Pfad im geführten Player.
**Weiter bearbeiten** stellt den eigenen Node-Aufbau vor dem Test wieder her.
**Katalog exportieren** erstellt die veröffentlichbare `workshops.json`.

## Deklarativ im Quellcode

Die offiziellen Workshops stammen aus `assets/workshops/workshops.json`.
Ihre Übersicht und ihr Fortschritt verwenden stabile Workshop- und Schritt-IDs.
Heruntergeladene Workshops sind nach Inhalt getrennt und haben einen eigenen
Fortschritt.

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
