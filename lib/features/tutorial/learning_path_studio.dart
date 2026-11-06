import 'package:flutter/material.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_interaction_editor.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_catalog.dart';

class LearningPathStudioDialog extends StatefulWidget {
  const LearningPathStudioDialog({
    required this.catalog,
    required this.paths,
    required this.workspaceNodes,
    required this.onSave,
    required this.onDelete,
    this.initialDraft,
    this.workspaceMode = LearningPathMode.simple,
    this.onEditWorkspace,
    this.onImport,
    this.onExport,
    this.onExportRemote,
    this.onShareClassroom,
    super.key,
  });

  final TranslationCatalog catalog;
  final List<AuthoredLearningPath> paths;
  final List<BlockNode> workspaceNodes;
  final LearningPathMode workspaceMode;
  final AuthoredLearningPath? initialDraft;
  final ValueChanged<AuthoredLearningPath>? onEditWorkspace;
  final Future<void> Function(AuthoredLearningPath path) onSave;
  final Future<void> Function(String id) onDelete;
  final Future<List<AuthoredLearningPath>> Function()? onImport;
  final Future<void> Function(List<AuthoredLearningPath> paths)? onExport;
  final Future<void> Function(AuthoredLearningPath path)? onExportRemote;
  final ValueChanged<AuthoredLearningPath>? onShareClassroom;

  @override
  State<LearningPathStudioDialog> createState() =>
      _LearningPathStudioDialogState();
}

class _LearningPathStudioDialogState extends State<LearningPathStudioDialog> {
  late List<AuthoredLearningPath> _paths;
  AuthoredLearningPath? _editing;

  TranslationCatalog get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    _paths = List<AuthoredLearningPath>.of(widget.paths);
    _editing = widget.initialDraft;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: _editing == null ? _buildLibrary() : _buildEditor(_editing),
      ),
    );
  }

  Widget _buildLibrary() {
    return Column(
      children: [
        _StudioHeader(
          title: catalog.text('tutorial.studio.title'),
          subtitle: catalog.text('tutorial.studio.subtitle'),
          onClose: () => Navigator.of(context).pop(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  key: const ValueKey('learning-path-create'),
                  onPressed: () => setState(() => _editing = _emptyPath()),
                  icon: const Icon(Icons.add),
                  label: Text(catalog.text('tutorial.studio.create')),
                ),
                if (widget.onImport != null)
                  TextButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(catalog.text('tutorial.studio.import')),
                  ),
                if (widget.onExport != null && _paths.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => widget.onExport!(_paths),
                    icon: const Icon(Icons.publish_outlined),
                    label: Text(catalog.text('tutorial.studio.export')),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _paths.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.route_outlined, size: 52),
                        const SizedBox(height: 14),
                        Text(
                          catalog.text('tutorial.studio.emptyTitle'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          catalog.text('tutorial.studio.emptyBody'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _paths.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _buildPathCard(_paths[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildPathCard(AuthoredLearningPath path) {
    final title = path.titleFor(catalog.locale);
    final description = path.descriptionFor(catalog.locale);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.timeline_rounded)),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${description.isEmpty ? '' : '$description\n'}'
                '${path.steps.length} ${catalog.text('tutorial.studio.steps')} · '
                '${path.calloutCount} ${catalog.text('tutorial.studio.callouts')}',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _editing = path),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(catalog.text('tutorial.studio.edit')),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(path),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(catalog.text('tutorial.studio.start')),
                ),
                if (widget.onShareClassroom != null)
                  TextButton.icon(
                    onPressed: () => widget.onShareClassroom!(path),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(catalog.text('tutorial.classroom.share')),
                  ),
                if (widget.onExportRemote != null)
                  IconButton(
                    tooltip: catalog.text('tutorial.download.export'),
                    onPressed: () => _exportRemote(path),
                    icon: const Icon(Icons.save_alt_rounded),
                  ),
                IconButton(
                  tooltip: catalog.text('tutorial.studio.delete'),
                  onPressed: () => _delete(path),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(AuthoredLearningPath? path) {
    return _LearningPathEditor(
      key: ValueKey(path?.id ?? 'new'),
      catalog: catalog,
      initialPath: path!,
      workspaceNodes: widget.workspaceNodes,
      workspaceMode: widget.workspaceMode,
      onEditWorkspace: widget.onEditWorkspace,
      onCancel: () => setState(() => _editing = null),
      onSave: (next, tryWorkshop) async {
        await widget.onSave(next);
        if (!mounted) return;
        if (tryWorkshop) {
          Navigator.of(context).pop(next);
          return;
        }
        setState(() {
          _paths = [
            next,
            for (final existing in _paths)
              if (existing.id != next.id) existing,
          ];
          _editing = null;
        });
      },
    );
  }

  AuthoredLearningPath _emptyPath() => AuthoredLearningPath(
    id: learningPathId('learning-path'),
    title: '',
    description: '',
    steps: const <LearningPathStep>[],
  );

  Future<void> _delete(AuthoredLearningPath path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(catalog.text('tutorial.studio.deleteTitle')),
        content: Text(
          catalog.text('tutorial.studio.deleteBody', {'title': path.title}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(catalog.text('tutorial.studio.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(catalog.text('tutorial.studio.deleteConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onDelete(path.id);
    if (!mounted) return;
    setState(() => _paths.removeWhere((item) => item.id == path.id));
  }

  Future<void> _import() async {
    final paths = await widget.onImport?.call();
    if (paths == null || !mounted) return;
    setState(() => _paths = List<AuthoredLearningPath>.of(paths));
  }

  Future<void> _exportRemote(AuthoredLearningPath path) async {
    try {
      await widget.onExportRemote!(path);
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(catalog.text('tutorial.download.exportError'))),
      );
    }
  }
}

class _LearningPathEditor extends StatefulWidget {
  const _LearningPathEditor({
    required this.catalog,
    required this.initialPath,
    required this.workspaceNodes,
    required this.workspaceMode,
    required this.onEditWorkspace,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final TranslationCatalog catalog;
  final AuthoredLearningPath initialPath;
  final List<BlockNode> workspaceNodes;
  final LearningPathMode workspaceMode;
  final ValueChanged<AuthoredLearningPath>? onEditWorkspace;
  final VoidCallback onCancel;
  final Future<void> Function(AuthoredLearningPath path, bool tryWorkshop)
  onSave;

  @override
  State<_LearningPathEditor> createState() => _LearningPathEditorState();
}

class _LearningPathEditorState extends State<_LearningPathEditor> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final List<LearningPathStep> _steps;
  bool _saving = false;
  bool _saveFailed = false;

  TranslationCatalog get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialPath.title);
    _description = TextEditingController(text: widget.initialPath.description);
    _steps = List<LearningPathStep>.of(widget.initialPath.steps);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasName = _title.text.trim().isNotEmpty;
    final canSave = !_saving && hasName && _steps.isNotEmpty;
    final message = _saveFailed
        ? 'tutorial.studio.saveFailed'
        : !hasName
        ? 'tutorial.studio.needsTitle'
        : _steps.isEmpty
        ? 'tutorial.studio.needsStep'
        : null;
    return Column(
      children: [
        _StudioHeader(
          title: catalog.text('tutorial.studio.editorTitle'),
          subtitle: catalog.text('tutorial.studio.editorSubtitle'),
          onBack: _saving ? null : widget.onCancel,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _StudioSectionTitle(
                number: 1,
                title: catalog.text('tutorial.studio.nameSection'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('learning-path-title'),
                controller: _title,
                autofocus: !hasName,
                enabled: !_saving,
                onChanged: (_) => setState(() => _saveFailed = false),
                decoration: InputDecoration(
                  labelText: catalog.text('tutorial.studio.pathTitle'),
                  hintText: catalog.text('tutorial.studio.pathTitleExample'),
                  border: const OutlineInputBorder(),
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(catalog.text('tutorial.studio.pathDescription')),
                initiallyExpanded: _description.text.isNotEmpty,
                children: [
                  TextField(
                    controller: _description,
                    enabled: !_saving,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: catalog.text(
                        'tutorial.studio.descriptionLabel',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _StudioSectionTitle(
                number: 2,
                title: catalog.text('tutorial.studio.timeline'),
              ),
              const SizedBox(height: 12),
              if (_steps.isEmpty)
                _StudioNotice(
                  icon: Icons.layers_outlined,
                  text: catalog.text('tutorial.studio.noSteps'),
                ),
              for (var index = 0; index < _steps.length; index++)
                _StepTile(
                  index: index,
                  step: _steps[index],
                  catalog: catalog,
                  onEdit: _saving ? null : () => _openStep(index),
                  onDelete: _saving
                      ? null
                      : () => setState(() => _steps.removeAt(index)),
                  onUp: _saving || index == 0
                      ? null
                      : () => _move(index, index - 1),
                  onDown: _saving || index == _steps.length - 1
                      ? null
                      : () => _move(index, index + 1),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('learning-path-add-step'),
                    onPressed: _saving ? null : () => _openStep(),
                    icon: const Icon(Icons.add),
                    label: Text(catalog.text('tutorial.studio.addStep')),
                  ),
                  if (widget.onEditWorkspace != null)
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => widget.onEditWorkspace!(_draft()),
                      icon: const Icon(Icons.dashboard_outlined),
                      label: Text(
                        catalog.text('tutorial.studio.editWorkspace'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null)
                Text(
                  catalog.text(message),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: _saveFailed
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const ValueKey('learning-path-save'),
                    onPressed: canSave ? () => _save(tryWorkshop: false) : null,
                    child: Text(catalog.text('tutorial.studio.save')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('learning-path-try'),
                    onPressed: canSave ? () => _save(tryWorkshop: true) : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(catalog.text('tutorial.studio.saveAndTry')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openStep([int? index]) async {
    final step = await showDialog<LearningPathStep>(
      context: context,
      builder: (_) => _LearningPathStepDialog(
        catalog: catalog,
        workspaceNodes: widget.workspaceNodes,
        workspaceMode: widget.workspaceMode,
        stepNumber: index == null ? _steps.length + 1 : index + 1,
        initialStep: index == null ? null : _steps[index],
      ),
    );
    if (step == null || !mounted) return;
    setState(() {
      if (index == null) {
        _steps.add(step);
      } else {
        _steps[index] = step;
      }
    });
  }

  void _move(int from, int to) {
    setState(() {
      final step = _steps.removeAt(from);
      _steps.insert(to, step);
    });
  }

  AuthoredLearningPath _draft() {
    final original = widget.initialPath;
    final title = _title.text.trim();
    final description = _description.text.trim();
    return AuthoredLearningPath(
      id: original.id,
      title: title,
      description: description,
      titleTranslations: title == original.title
          ? original.titleTranslations
          : const {},
      descriptionTranslations: description == original.description
          ? original.descriptionTranslations
          : const {},
      steps: List.unmodifiable(_steps),
    );
  }

  Future<void> _save({required bool tryWorkshop}) async {
    final draft = _draft();
    if (_saving || draft.title.isEmpty || draft.steps.isEmpty) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.onSave(draft, tryWorkshop);
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }
}

class _LearningPathStepDialog extends StatefulWidget {
  const _LearningPathStepDialog({
    required this.catalog,
    required this.workspaceNodes,
    required this.workspaceMode,
    required this.stepNumber,
    this.initialStep,
  });

  final TranslationCatalog catalog;
  final List<BlockNode> workspaceNodes;
  final LearningPathMode workspaceMode;
  final int stepNumber;
  final LearningPathStep? initialStep;

  @override
  State<_LearningPathStepDialog> createState() =>
      _LearningPathStepDialogState();
}

class _LearningPathStepDialogState extends State<_LearningPathStepDialog> {
  late final TextEditingController _title;
  late final TextEditingController _instruction;
  late final TextEditingController _hint;
  final _calloutTitle = TextEditingController();
  final _calloutBody = TextEditingController();
  late List<LearningPathNodeTemplate> _nodes;
  late final LearningPathNodeTemplate? _startNode;
  late Set<String> _selectedRefs;
  late final List<LearningPathNodeCallout> _callouts;
  late final Set<String> _highlights;
  late List<LearningPathRequirement> _requirements;
  String? _targetRef;
  LearningPathCalloutSide _side = LearningPathCalloutSide.right;

  TranslationCatalog get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStep;
    _title = TextEditingController(text: initial?.title ?? '');
    _instruction = TextEditingController(text: initial?.instruction ?? '');
    _hint = TextEditingController(text: initial?.hint ?? '');
    _callouts = List.of(initial?.callouts ?? const <LearningPathNodeCallout>[]);
    _highlights = {...?initial?.highlights};
    _requirements = [...?initial?.requirements];
    final savedStart = initial?.nodes
        .where((node) => node.type == BlockType.eventGreenFlag)
        .firstOrNull;
    final workspaceStart = widget.workspaceNodes
        .where((node) => node.type == BlockType.eventGreenFlag)
        .firstOrNull;
    _startNode =
        savedStart ??
        (workspaceStart == null
            ? null
            : LearningPathNodeTemplate(
                ref: workspaceStart.id,
                type: workspaceStart.type,
              ));
    _selectNodes(
      initial?.nodes
              .where((node) => node.type != BlockType.eventGreenFlag)
              .toList() ??
          _workspaceTemplates(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _instruction.dispose();
    _hint.dispose();
    _calloutTitle.dispose();
    _calloutBody.dispose();
    super.dispose();
  }

  List<LearningPathNodeTemplate> _workspaceTemplates() {
    final nodes = <String, BlockNode>{
      for (final block in widget.workspaceNodes)
        for (final node in [block, ...embeddedReporters(block)])
          if (node.type != BlockType.eventGreenFlag) node.id: node,
    };
    return [
      for (final node in nodes.values)
        LearningPathNodeTemplate(
          ref: node.id,
          type: node.type,
          defaults: learningPathNodeDefaults(node)
            ..remove(reporterInputsKey)
            ..remove(columnSourceNodeInput),
        ),
    ];
  }

  bool _isInteractionRef(String ref) =>
      ref == _startNode?.ref || _selectedRefs.contains(ref);

  Iterable<LearningPathRequirement> get _selectedRequirements =>
      _requirements.where((rule) => rule.refs.every(_isInteractionRef));

  void _selectNodes(List<LearningPathNodeTemplate> nodes) {
    _nodes = nodes;
    _selectedRefs = nodes.map((node) => node.ref).toSet();
    _targetRef = nodes.firstOrNull?.ref;
  }

  void _toggleNode(LearningPathNodeTemplate node, bool selected) {
    setState(() {
      if (selected) {
        _selectedRefs.add(node.ref);
      } else {
        _selectedRefs.remove(node.ref);
      }
      if (!_selectedRefs.contains(_targetRef)) {
        _targetRef = _nodes
            .where((node) => _selectedRefs.contains(node.ref))
            .firstOrNull
            ?.ref;
      }
    });
  }

  String _nodeLabel(LearningPathNodeTemplate node) {
    final label = sqlLabelFor(
      node.type,
      SqlAbstractionMode.advanced,
      node.defaults,
      catalog.locale,
    );
    return label
        .split('\n')
        .first
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]|\{([^}]+)\}'),
          (match) =>
              node.defaults[sqlInputKey((match[1] ?? match[2])!)]?.toString() ??
              match[0]!,
        );
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _title.text.trim().isNotEmpty && _instruction.text.trim().isNotEmpty;
    final canReplaceNodes =
        widget.initialStep != null &&
        widget.workspaceNodes.any(
          (node) => node.type != BlockType.eventGreenFlag,
        );
    return AlertDialog(
      scrollable: true,
      title: Text(
        catalog.text('tutorial.studio.stepEditor', {
          'number': widget.stepNumber,
        }),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(catalog.text('tutorial.studio.stepHelp')),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('learning-step-title'),
              controller: _title,
              autofocus: widget.initialStep == null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: catalog.text('tutorial.studio.stepTitle'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('learning-step-instruction'),
              controller: _instruction,
              onChanged: (_) => setState(() {}),
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: catalog.text('tutorial.studio.instruction'),
                hintText: catalog.text('tutorial.studio.instructionExample'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(catalog.text('tutorial.studio.hint')),
              initiallyExpanded: _hint.text.isNotEmpty,
              children: [
                TextField(
                  controller: _hint,
                  decoration: InputDecoration(
                    labelText: catalog.text('tutorial.studio.hintLabel'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            if (_nodes.isNotEmpty || canReplaceNodes)
              ExpansionTile(
                key: const ValueKey('learning-step-nodes'),
                tilePadding: EdgeInsets.zero,
                title: Text(catalog.text('tutorial.studio.practiceNodes')),
                subtitle: Text(
                  catalog.text('tutorial.studio.nodeSnapshot', {
                    'count': _selectedRefs.length,
                  }),
                ),
                children: [
                  for (final node in _nodes)
                    CheckboxListTile(
                      key: ValueKey('learning-step-node-${node.ref}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _nodeLabel(node),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: _selectedRefs.contains(node.ref),
                      onChanged: (selected) =>
                          _toggleNode(node, selected == true),
                    ),
                  if (canReplaceNodes)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _selectNodes(_workspaceTemplates())),
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        catalog.text('tutorial.studio.useWorkspaceNodes'),
                      ),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  catalog.text('tutorial.studio.noNodes'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            LearningPathInteractionEditor(
              catalog: catalog,
              mode:
                  (widget.initialStep?.mode ?? widget.workspaceMode) ==
                      LearningPathMode.simple
                  ? SqlAbstractionMode.simple
                  : SqlAbstractionMode.advanced,
              nodes: [
                ?_startNode,
                ..._nodes.where((node) => _selectedRefs.contains(node.ref)),
              ],
              nodeLabel: _nodeLabel,
              highlights: _highlights.where(_isInteractionRef).toSet(),
              requirements: _selectedRequirements.toList(),
              onHighlight: (ref) => setState(() {
                if (!_highlights.add(ref)) _highlights.remove(ref);
              }),
              onRequirementsChanged: (rules) =>
                  setState(() => _requirements = rules),
            ),
            if (_selectedRefs.isNotEmpty)
              ExpansionTile(
                key: const ValueKey('learning-step-callouts'),
                tilePadding: EdgeInsets.zero,
                title: Text(catalog.text('tutorial.studio.explainNodes')),
                initiallyExpanded: _callouts.isNotEmpty,
                children: _buildCalloutControls(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(catalog.text('tutorial.studio.cancel')),
        ),
        FilledButton(
          key: const ValueKey('learning-step-apply'),
          onPressed: canSave ? _save : null,
          child: Text(catalog.text('tutorial.studio.applyStep')),
        ),
      ],
    );
  }

  List<Widget> _buildCalloutControls() => [
    DropdownButtonFormField<String>(
      key: ValueKey(_targetRef),
      initialValue: _targetRef,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: catalog.text('tutorial.studio.targetNode'),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final node in _nodes)
          if (_selectedRefs.contains(node.ref))
            DropdownMenuItem(
              value: node.ref,
              child: Text(
                _nodeLabel(node),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
      onChanged: (value) => _targetRef = value,
    ),
    const SizedBox(height: 10),
    TextField(
      key: const ValueKey('learning-callout-title'),
      controller: _calloutTitle,
      decoration: InputDecoration(
        labelText: catalog.text('tutorial.studio.calloutTitle'),
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 10),
    TextField(
      key: const ValueKey('learning-callout-body'),
      controller: _calloutBody,
      decoration: InputDecoration(
        labelText: catalog.text('tutorial.studio.calloutBody'),
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final side in LearningPathCalloutSide.values)
          ChoiceChip(
            label: Text(catalog.text('tutorial.studio.${side.name}')),
            selected: _side == side,
            onSelected: (_) => setState(() => _side = side),
          ),
        TextButton.icon(
          key: const ValueKey('learning-callout-add'),
          onPressed: _addCallout,
          icon: const Icon(Icons.add_comment_outlined),
          label: Text(catalog.text('tutorial.studio.addCallout')),
        ),
      ],
    ),
    for (final callout in _callouts)
      if (_selectedRefs.contains(callout.targetRef))
        ListTile(
          title: Text(callout.title),
          subtitle: Text(callout.body),
          trailing: IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: () => setState(() => _callouts.remove(callout)),
            icon: const Icon(Icons.close),
          ),
        ),
  ];

  void _addCallout() {
    final targetRef = _targetRef;
    final title = _calloutTitle.text.trim();
    final body = _calloutBody.text.trim();
    if (targetRef == null ||
        !_selectedRefs.contains(targetRef) ||
        title.isEmpty ||
        body.isEmpty) {
      return;
    }
    setState(() {
      _callouts.add(
        LearningPathNodeCallout(
          id: 'callout-${DateTime.now().microsecondsSinceEpoch}',
          targetRef: targetRef,
          title: title,
          body: body,
          side: _side,
        ),
      );
      _calloutTitle.clear();
      _calloutBody.clear();
    });
  }

  void _save() {
    final title = _title.text.trim();
    final instruction = _instruction.text.trim();
    if (title.isEmpty || instruction.isEmpty) return;
    _addCallout();
    final start = _startNode;
    final keepStart =
        start != null &&
        (_highlights.contains(start.ref) ||
            _selectedRequirements.any(
              (rule) => rule.refs.contains(start.ref),
            ) ||
            _callouts.any((callout) => callout.targetRef == start.ref) ||
            widget.initialStep?.nodes.any((node) => node.ref == start.ref) ==
                true);
    Navigator.of(context).pop(
      LearningPathStep(
        id:
            widget.initialStep?.id ??
            'step-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        instruction: instruction,
        hint: _hint.text.trim(),
        mode: widget.initialStep?.mode ?? widget.workspaceMode,
        nodes: List.unmodifiable([
          if (keepStart) start,
          ..._nodes.where((node) => _selectedRefs.contains(node.ref)),
        ]),
        callouts: List.unmodifiable(
          _callouts.where((callout) => _isInteractionRef(callout.targetRef)),
        ),
        highlights: List.unmodifiable(_highlights.where(_isInteractionRef)),
        requirements: List.unmodifiable(_selectedRequirements),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.step,
    required this.catalog,
    required this.onEdit,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final LearningPathStep step;
  final TranslationCatalog catalog;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          step.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          step.instruction,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onEdit,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: catalog.text('tutorial.studio.editStep'),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<VoidCallback>(
              enabled: onDelete != null,
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                if (onUp != null)
                  PopupMenuItem(
                    value: onUp,
                    child: Text(catalog.text('tutorial.studio.moveStepUp')),
                  ),
                if (onDown != null)
                  PopupMenuItem(
                    value: onDown,
                    child: Text(catalog.text('tutorial.studio.moveStepDown')),
                  ),
                PopupMenuItem(
                  value: onDelete,
                  child: Text(catalog.text('tutorial.studio.deleteStep')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioSectionTitle extends StatelessWidget {
  const _StudioSectionTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(radius: 13, child: Text('$number')),
      const SizedBox(width: 10),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );
}

class _StudioHeader extends StatelessWidget {
  const _StudioHeader({
    required this.title,
    required this.subtitle,
    this.onBack,
    this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
              icon: const Icon(Icons.arrow_back),
            ),
          const Icon(Icons.route_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _StudioNotice extends StatelessWidget {
  const _StudioNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
