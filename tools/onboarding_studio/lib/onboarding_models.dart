import 'dart:convert';

enum WalkthroughTarget {
  nodePalette,
  workspace,
  databaseTools,
  workshop;

  String get label => switch (this) {
    WalkthroughTarget.nodePalette => 'Node-Leiste',
    WalkthroughTarget.workspace => 'Node-Arbeitsfläche',
    WalkthroughTarget.databaseTools => 'Datenbank-Tools',
    WalkthroughTarget.workshop => 'Workshop-Button',
  };
}

enum TooltipPlacement {
  top,
  bottom;

  String get label => this == TooltipPlacement.top ? 'Oben' : 'Unten';
}

class WalkthroughStep {
  const WalkthroughStep({
    required this.id,
    required this.target,
    required this.title,
    required this.message,
    required this.placement,
  });

  final String id;
  final WalkthroughTarget target;
  final String title;
  final String message;
  final TooltipPlacement placement;

  WalkthroughStep copyWith({
    WalkthroughTarget? target,
    String? title,
    String? message,
    TooltipPlacement? placement,
  }) => WalkthroughStep(
    id: id,
    target: target ?? this.target,
    title: title ?? this.title,
    message: message ?? this.message,
    placement: placement ?? this.placement,
  );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'target': target.name,
    'title': title,
    'message': message,
    'placement': placement.name,
  };
}

class WalkthroughDefinition {
  const WalkthroughDefinition({required this.name, required this.steps});

  final String name;
  final List<WalkthroughStep> steps;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': 1,
    'name': name,
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

const exampleWalkthrough = WalkthroughDefinition(
  name: 'Erste Schritte',
  steps: <WalkthroughStep>[
    WalkthroughStep(
      id: 'find-nodes',
      target: WalkthroughTarget.nodePalette,
      title: 'Nodes auswählen',
      message:
          'In der Node-Leiste findest du Bausteine für Abfragen, Filter und Datenänderungen.',
      placement: TooltipPlacement.bottom,
    ),
    WalkthroughStep(
      id: 'build-query',
      target: WalkthroughTarget.workspace,
      title: 'Nodes verbinden',
      message:
          'Ziehe Nodes auf die Arbeitsfläche und verbinde sie zu einer ausführbaren Abfrage.',
      placement: TooltipPlacement.top,
    ),
    WalkthroughStep(
      id: 'use-tools',
      target: WalkthroughTarget.databaseTools,
      title: 'Datenbank-Tools verwenden',
      message:
          'Binde eine SQLite-Datei ein, prüfe Tabellen und führe deine generierte Abfrage aus.',
      placement: TooltipPlacement.bottom,
    ),
    WalkthroughStep(
      id: 'learn-in-workshop',
      target: WalkthroughTarget.workshop,
      title: 'Im Workshop üben',
      message:
          'Der Workshop erklärt NodeQL mit kleinen Übungen, ohne dein aktuelles Projekt zu verändern.',
      placement: TooltipPlacement.bottom,
    ),
  ],
);
