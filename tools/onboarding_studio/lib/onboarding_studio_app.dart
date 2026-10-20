import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'onboarding_models.dart';

class OnboardingStudioApp extends StatelessWidget {
  const OnboardingStudioApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NodeQL Onboarding Studio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.dark,
      ),
    ),
    home: const OnboardingStudioPage(),
  );
}

class OnboardingStudioPage extends StatefulWidget {
  const OnboardingStudioPage({super.key});

  @override
  State<OnboardingStudioPage> createState() => _OnboardingStudioPageState();
}

class _OnboardingStudioPageState extends State<OnboardingStudioPage> {
  late List<WalkthroughStep> _steps;
  var _selectedIndex = 0;
  var _previewing = false;
  var _name = exampleWalkthrough.name;

  @override
  void initState() {
    super.initState();
    _steps = List<WalkthroughStep>.of(exampleWalkthrough.steps);
  }

  WalkthroughDefinition get _definition => WalkthroughDefinition(
    name: _name.trim().isEmpty ? 'Unbenanntes Onboarding' : _name.trim(),
    steps: _steps,
  );

  WalkthroughStep get _selected => _steps[_selectedIndex];

  void _updateSelected(WalkthroughStep step) {
    setState(() => _steps[_selectedIndex] = step);
  }

  void _addStep() {
    final step = WalkthroughStep(
      id: 'step-${_steps.length + 1}',
      target: WalkthroughTarget.workspace,
      title: 'Neuer Schritt',
      message: 'Erkläre hier, was Nutzer:innen an dieser Stelle tun können.',
      placement: TooltipPlacement.bottom,
    );
    setState(() {
      _steps = <WalkthroughStep>[..._steps, step];
      _selectedIndex = _steps.length - 1;
    });
  }

  void _removeSelected() {
    if (_steps.length == 1) return;
    setState(() {
      _steps.removeAt(_selectedIndex);
      _selectedIndex = _selectedIndex.clamp(0, _steps.length - 1);
    });
  }

  void _moveSelected(int offset) {
    final nextIndex = _selectedIndex + offset;
    if (nextIndex < 0 || nextIndex >= _steps.length) return;
    setState(() {
      final step = _steps.removeAt(_selectedIndex);
      _steps.insert(nextIndex, step);
      _selectedIndex = nextIndex;
    });
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: _definition.toPrettyJson()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Walkthrough-JSON wurde kopiert.')),
      );
    }
  }

  Future<void> _exportJson() async {
    final target = await FilePicker.platform.saveFile(
      dialogTitle: 'Onboarding-Walkthrough exportieren',
      fileName: 'nodeql_onboarding.json',
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (target == null) return;
    await File(target).writeAsString(_definition.toPrettyJson(), flush: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exportiert: $target')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Onboarding Studio'),
          Text(
            'Privates Entwicklerwerkzeug · nicht Teil des NodeQL-Releases',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _copyJson,
          icon: const Icon(Icons.content_copy_outlined),
          label: const Text('JSON kopieren'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _exportJson,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('JSON exportieren'),
        ),
        const SizedBox(width: 18),
      ],
    ),
    body: Row(
      children: [
        SizedBox(
          width: 292,
          child: _StepList(
            steps: _steps,
            selectedIndex: _selectedIndex,
            onSelected: (index) => setState(() => _selectedIndex = index),
            onAdd: _addStep,
            onMoveUp: () => _moveSelected(-1),
            onMoveDown: () => _moveSelected(1),
            onDelete: _removeSelected,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _PreviewToolbar(
                  previewing: _previewing,
                  onPreviewChanged: (value) =>
                      setState(() => _previewing = value),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _WalkthroughPreview(
                    step: _selected,
                    previewing: _previewing,
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 330,
          child: _StepInspector(
            definitionName: _name,
            step: _selected,
            onNameChanged: (name) => setState(() => _name = name),
            onStepChanged: _updateSelected,
          ),
        ),
      ],
    ),
  );
}

class _StepList extends StatelessWidget {
  const _StepList({
    required this.steps,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAdd,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final List<WalkthroughStep> steps;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 22, 20, 6),
          child: Text(
            'Walkthrough-Schritte',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Die Reihenfolge entspricht der späteren Anleitung.'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: steps.length,
            itemBuilder: (context, index) {
              final step = steps[index];
              final selected = index == selectedIndex;
              return Card(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  onTap: () => onSelected(index),
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(
                    step.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    step.target.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Schritt'),
              ),
              IconButton(
                onPressed: onMoveUp,
                tooltip: 'Nach oben',
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                onPressed: onMoveDown,
                tooltip: 'Nach unten',
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                onPressed: steps.length == 1 ? null : onDelete,
                tooltip: 'Schritt löschen',
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PreviewToolbar extends StatelessWidget {
  const _PreviewToolbar({
    required this.previewing,
    required this.onPreviewChanged,
  });

  final bool previewing;
  final ValueChanged<bool> onPreviewChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Live-Vorschau', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Zielbereich in der Vorschau prüfen und rechts konfigurieren.',
      ),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.design_services_outlined),
            label: Text('Bearbeiten'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.play_circle_outline),
            label: Text('Vorschau abspielen'),
          ),
        ],
        selected: {previewing},
        onSelectionChanged: (selection) => onPreviewChanged(selection.first),
      ),
    ],
  );
}

class _StepInspector extends StatelessWidget {
  const _StepInspector({
    required this.definitionName,
    required this.step,
    required this.onNameChanged,
    required this.onStepChanged,
  });

  final String definitionName;
  final WalkthroughStep step;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<WalkthroughStep> onStepChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: ListView(
      children: [
        Text('Eigenschaften', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 22),
        TextField(
          controller: TextEditingController(
            text: definitionName,
          )..selection = TextSelection.collapsed(offset: definitionName.length),
          onChanged: onNameChanged,
          decoration: const InputDecoration(labelText: 'Name des Onboardings'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(),
        ),
        Text('Aktiver Schritt', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 14),
        DropdownButtonFormField<WalkthroughTarget>(
          key: ValueKey<String>('onboarding-step-target-${step.id}'),
          initialValue: step.target,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Hervorgehobenes Element',
          ),
          items: WalkthroughTarget.values
              .map(
                (target) => DropdownMenuItem(
                  value: target,
                  child: Text(target.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: (target) {
            if (target != null) {
              onStepChanged(step.copyWith(target: target));
            }
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: ValueKey<String>('onboarding-step-title-${step.id}'),
          initialValue: step.title,
          onChanged: (title) => onStepChanged(step.copyWith(title: title)),
          decoration: const InputDecoration(labelText: 'Titel'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: ValueKey<String>('onboarding-step-message-${step.id}'),
          initialValue: step.message,
          minLines: 3,
          maxLines: 5,
          onChanged: (message) =>
              onStepChanged(step.copyWith(message: message)),
          decoration: const InputDecoration(labelText: 'Erklärung'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<TooltipPlacement>(
          key: ValueKey<String>('onboarding-step-placement-${step.id}'),
          initialValue: step.placement,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tooltip-Position'),
          items: TooltipPlacement.values
              .map(
                (placement) => DropdownMenuItem(
                  value: placement,
                  child: Text(placement.label),
                ),
              )
              .toList(growable: false),
          onChanged: (placement) {
            if (placement != null) {
              onStepChanged(step.copyWith(placement: placement));
            }
          },
        ),
      ],
    ),
  );
}

class _WalkthroughPreview extends StatelessWidget {
  const _WalkthroughPreview({required this.step, required this.previewing});

  final WalkthroughStep step;
  final bool previewing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final targetRect = _targetRect(step.target, constraints.biggest);
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _MockNodeQlInterface()),
              if (previewing)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xA6000000)),
                ),
              Positioned.fromRect(
                rect: targetRect.inflate(5),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF67E8F9),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22D3EE).withValues(alpha: .45),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (targetRect.left + targetRect.width / 2 - 140).clamp(
                  14.0,
                  constraints.maxWidth - 294.0,
                ),
                top: _tooltipTop(
                  step.placement,
                  targetRect,
                  constraints.maxHeight,
                ),
                child: _TooltipCard(step: step, previewing: previewing),
              ),
            ],
          ),
        ),
      );
    },
  );

  double _tooltipTop(TooltipPlacement placement, Rect target, double height) {
    final wanted = placement == TooltipPlacement.top
        ? target.top - 164
        : target.bottom + 16;
    return wanted.clamp(14.0, height - 152.0);
  }

  Rect _targetRect(WalkthroughTarget target, Size size) => switch (target) {
    WalkthroughTarget.databaseTools => const Rect.fromLTWH(22, 56, 262, 40),
    WalkthroughTarget.workshop => Rect.fromLTWH(size.width - 150, 56, 126, 40),
    WalkthroughTarget.nodePalette => Rect.fromLTWH(
      22,
      120,
      154,
      size.height - 142,
    ),
    WalkthroughTarget.workspace => Rect.fromLTWH(
      190,
      120,
      size.width - 212,
      size.height - 142,
    ),
  };
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({required this.step, required this.previewing});

  final WalkthroughStep step;
  final bool previewing;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 12,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(step.message),
          if (previewing) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {},
                child: const Text('Weiter'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MockNodeQlInterface extends StatelessWidget {
  const _MockNodeQlInterface();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF111827),
    child: Column(
      children: [
        Container(
          height: 112,
          color: const Color(0xFF0B1220),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                const Icon(Icons.account_tree_rounded, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'NodeQL',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 22),
                _mockButton(Icons.storage_outlined, '.db einbinden'),
                const SizedBox(width: 8),
                _mockButton(Icons.table_chart_outlined, 'Tabellen'),
                const SizedBox(width: 8),
                _mockButton(
                  Icons.play_arrow_rounded,
                  'SQLite ausführen',
                  filled: true,
                ),
                const SizedBox(width: 120),
                _mockButton(Icons.school_rounded, 'Workshop', filled: true),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Container(
                  width: 154,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF172033),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NODES',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 12),
                      _MockNodeTile('Abfrage', Color(0xFF2563EB)),
                      SizedBox(height: 8),
                      _MockNodeTile('Filter', Color(0xFF0284C7)),
                      SizedBox(height: 8),
                      _MockNodeTile('Sortieren', Color(0xFF7C3AED)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Text(
                          'SELECT\ncustomers',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _mockButton(IconData icon, String label, {bool filled = false}) =>
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: filled
              ? const Color(0xFF2563EB)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      );
}

class _MockNodeTile extends StatelessWidget {
  const _MockNodeTile(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
