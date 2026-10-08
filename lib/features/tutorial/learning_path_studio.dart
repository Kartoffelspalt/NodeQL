import 'package:flutter/material.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/localization/translation_catalog.dart';

class LearningPathStudioDialog extends StatefulWidget {
  const LearningPathStudioDialog({
    required this.catalog,
    required this.paths,
    required this.workspaceNodes,
    required this.onSave,
    required this.onDelete,
    this.onImport,
    this.onExport,
    super.key,
  });

  final TranslationCatalog catalog;
  final List<AuthoredLearningPath> paths;
  final List<BlockNode> workspaceNodes;
  final Future<void> Function(AuthoredLearningPath path) onSave;
  final Future<void> Function(String id) onDelete;
  final Future<List<AuthoredLearningPath>> Function()? onImport;
  final Future<void> Function(List<AuthoredLearningPath> paths)? onExport;

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
                  itemBuilder: (context, index) {
                    final path = _paths[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.timeline_rounded),
                        ),
                        title: Text(
                          path.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${path.description}\n'
                          '${path.steps.length} ${catalog.text('tutorial.studio.steps')} · '
                          '${path.calloutCount} ${catalog.text('tutorial.studio.callouts')}',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: catalog.text('tutorial.studio.edit'),
                              onPressed: () => setState(() => _editing = path),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: catalog.text('tutorial.studio.delete'),
                              onPressed: () => _delete(path),
                              icon: const Icon(Icons.delete_outline),
                            ),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).pop(path),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                catalog.text('tutorial.studio.start'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  catalog.text('tutorial.studio.workspaceHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              if (widget.onImport != null) ...[
                OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(catalog.text('tutorial.studio.import')),
                ),
                const SizedBox(width: 8),
              ],
              if (widget.onExport != null && _paths.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => widget.onExport!(_paths),
                  icon: const Icon(Icons.publish_outlined),
                  label: Text(catalog.text('tutorial.studio.export')),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.icon(
                key: const ValueKey('learning-path-create'),
                onPressed: () => setState(() => _editing = _emptyPath()),
                icon: const Icon(Icons.add_road_rounded),
                label: Text(catalog.text('tutorial.studio.create')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(AuthoredLearningPath? path) {
    return _LearningPathEditor(
      key: ValueKey(path?.id ?? 'new'),
      catalog: catalog,
      initialPath: path!,
      workspaceNodes: widget.workspaceNodes,
      onCancel: () => setState(() => _editing = null),
      onSave: (next) async {
        await widget.onSave(next);
        if (!mounted) return;
        setState(() {
          _paths = [
            for (final existing in _paths)
              if (existing.id != next.id) existing,
            next,
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
}

class _LearningPathEditor extends StatefulWidget {
  const _LearningPathEditor({
    required this.catalog,
    required this.initialPath,
    required this.workspaceNodes,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final TranslationCatalog catalog;
  final AuthoredLearningPath initialPath;
  final List<BlockNode> workspaceNodes;
  final VoidCallback onCancel;
  final Future<void> Function(AuthoredLearningPath path) onSave;

  @override
  State<_LearningPathEditor> createState() => _LearningPathEditorState();
}

class _LearningPathEditorState extends State<_LearningPathEditor> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late List<LearningPathStep> _steps;
  bool _saving = false;

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
    final catalog = widget.catalog;
    return Column(
      children: [
        _StudioHeader(
          title: catalog.text('tutorial.studio.editorTitle'),
          subtitle: catalog.text('tutorial.studio.editorSubtitle'),
          onBack: widget.onCancel,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('learning-path-title'),
                      controller: _title,
                      decoration: InputDecoration(
                        labelText: catalog.text('tutorial.studio.pathTitle'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _description,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: catalog.text(
                          'tutorial.studio.pathDescription',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      catalog.text('tutorial.studio.timeline'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('learning-path-add-step'),
                    onPressed: _addStep,
                    icon: const Icon(Icons.add),
                    label: Text(catalog.text('tutorial.studio.addStep')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_steps.isEmpty)
                _StudioNotice(
                  icon: Icons.layers_outlined,
                  text: catalog.text('tutorial.studio.noSteps'),
                )
              else
                for (var index = 0; index < _steps.length; index++)
                  _StepTile(
                    index: index,
                    step: _steps[index],
                    catalog: catalog,
                    onEdit: () => _editStep(index),
                    onDelete: () => setState(() => _steps.removeAt(index)),
                    onUp: index == 0 ? null : () => _move(index, index - 1),
                    onDown: index == _steps.length - 1
                        ? null
                        : () => _move(index, index + 1),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : widget.onCancel,
                child: Text(catalog.text('tutorial.studio.cancel')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('learning-path-save'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(catalog.text('tutorial.studio.save')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addStep() async {
    final step = await showDialog<LearningPathStep>(
      context: context,
      builder: (_) => _LearningPathStepDialog(
        catalog: widget.catalog,
        workspaceNodes: widget.workspaceNodes,
        stepNumber: _steps.length + 1,
      ),
    );
    if (step != null && mounted) setState(() => _steps.add(step));
  }

  Future<void> _editStep(int index) async {
    final step = await showDialog<LearningPathStep>(
      context: context,
      builder: (_) => _LearningPathStepDialog(
        catalog: widget.catalog,
        workspaceNodes: widget.workspaceNodes,
        stepNumber: index + 1,
        initialStep: _steps[index],
      ),
    );
    if (step != null && mounted) setState(() => _steps[index] = step);
  }

  void _move(int from, int to) {
    setState(() {
      final step = _steps.removeAt(from);
      _steps.insert(to, step);
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.catalog.text('tutorial.studio.invalid'))),
      );
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(
      AuthoredLearningPath(
        id: widget.initialPath.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        steps: List.unmodifiable(_steps),
      ),
    );
  }
}

class _LearningPathStepDialog extends StatefulWidget {
  const _LearningPathStepDialog({
    required this.catalog,
    required this.workspaceNodes,
    required this.stepNumber,
    this.initialStep,
  });

  final TranslationCatalog catalog;
  final List<BlockNode> workspaceNodes;
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
  late final TextEditingController _calloutTitle;
  late final TextEditingController _calloutBody;
  late final List<LearningPathNodeTemplate> _nodes;
  late List<LearningPathNodeCallout> _callouts;
  String? _targetRef;
  LearningPathCalloutSide _side = LearningPathCalloutSide.right;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStep;
    _title = TextEditingController(text: initial?.title ?? '');
    _instruction = TextEditingController(text: initial?.instruction ?? '');
    _hint = TextEditingController(text: initial?.hint ?? '');
    _calloutTitle = TextEditingController();
    _calloutBody = TextEditingController();
    _nodes =
        initial?.nodes.toList(growable: false) ??
        widget.workspaceNodes
            .where((node) => node.type != BlockType.eventGreenFlag)
            .map(
              (node) => LearningPathNodeTemplate(
                ref: node.id,
                type: node.type,
                defaults: learningPathNodeDefaults(node),
              ),
            )
            .toList(growable: false);
    _callouts = List<LearningPathNodeCallout>.of(
      initial?.callouts ?? const <LearningPathNodeCallout>[],
    );
    _targetRef = _nodes.firstOrNull?.ref;
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

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    return AlertDialog(
      title: Text(
        catalog.text('tutorial.studio.stepEditor', {
          'number': widget.stepNumber,
        }),
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('learning-step-title'),
                controller: _title,
                decoration: InputDecoration(
                  labelText: catalog.text('tutorial.studio.stepTitle'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('learning-step-instruction'),
                controller: _instruction,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: catalog.text('tutorial.studio.instruction'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hint,
                decoration: InputDecoration(
                  labelText: catalog.text('tutorial.studio.hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                catalog.text('tutorial.studio.nodeSnapshot', {
                  'count': _nodes.length,
                }),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (_nodes.isEmpty)
                _StudioNotice(
                  icon: Icons.info_outline,
                  text: catalog.text('tutorial.studio.noNodes'),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _targetRef,
                        decoration: InputDecoration(
                          labelText: catalog.text('tutorial.studio.targetNode'),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (var index = 0; index < _nodes.length; index++)
                            DropdownMenuItem(
                              value: _nodes[index].ref,
                              child: Text(
                                '${index + 1}. ${_nodes[index].type.name}',
                              ),
                            ),
                        ],
                        onChanged: (value) => _targetRef = value,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SegmentedButton<LearningPathCalloutSide>(
                      segments: [
                        ButtonSegment(
                          value: LearningPathCalloutSide.left,
                          label: Text(catalog.text('tutorial.studio.left')),
                        ),
                        ButtonSegment(
                          value: LearningPathCalloutSide.right,
                          label: Text(catalog.text('tutorial.studio.right')),
                        ),
                      ],
                      selected: <LearningPathCalloutSide>{_side},
                      onSelectionChanged: (selection) =>
                          setState(() => _side = selection.first),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('learning-callout-title'),
                        controller: _calloutTitle,
                        decoration: InputDecoration(
                          labelText: catalog.text(
                            'tutorial.studio.calloutTitle',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('learning-callout-body'),
                        controller: _calloutBody,
                        decoration: InputDecoration(
                          labelText: catalog.text(
                            'tutorial.studio.calloutBody',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      key: const ValueKey('learning-callout-add'),
                      tooltip: catalog.text('tutorial.studio.addCallout'),
                      onPressed: _addCallout,
                      icon: const Icon(Icons.add_comment_outlined),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              for (var index = 0; index < _callouts.length; index++)
                ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(_callouts[index].title),
                  subtitle: Text(_callouts[index].body),
                  trailing: IconButton(
                    onPressed: () => setState(() => _callouts.removeAt(index)),
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(catalog.text('tutorial.studio.cancel')),
        ),
        FilledButton(
          key: const ValueKey('learning-step-apply'),
          onPressed: _save,
          child: Text(catalog.text('tutorial.studio.applyStep')),
        ),
      ],
    );
  }

  void _addCallout() {
    final targetRef = _targetRef;
    final title = _calloutTitle.text.trim();
    final body = _calloutBody.text.trim();
    if (targetRef == null || title.isEmpty || body.isEmpty) return;
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
    if (_title.text.trim().isEmpty || _instruction.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      LearningPathStep(
        id:
            widget.initialStep?.id ??
            'step-${DateTime.now().microsecondsSinceEpoch}',
        title: _title.text.trim(),
        instruction: _instruction.text.trim(),
        hint: _hint.text.trim(),
        nodes: _nodes,
        callouts: List.unmodifiable(_callouts),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;
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
          '${step.instruction}\n${step.nodes.length} Nodes · '
          '${step.callouts.length} ${catalog.text('tutorial.studio.callouts')}',
        ),
        isThreeLine: true,
        trailing: Wrap(
          children: [
            IconButton(onPressed: onUp, icon: const Icon(Icons.arrow_upward)),
            IconButton(
              onPressed: onDown,
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(onPressed: onEdit, icon: const Icon(Icons.edit)),
            IconButton(onPressed: onDelete, icon: const Icon(Icons.delete)),
          ],
        ),
      ),
    );
  }
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
            IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
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
            IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
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
