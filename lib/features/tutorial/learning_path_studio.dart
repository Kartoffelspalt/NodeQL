import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_interaction_editor.dart';
import 'package:nodeql/features/tutorial/learning_path_review.dart';
import 'package:nodeql/features/tutorial/learning_path_studio_library.dart';

import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_catalog.dart';

part 'learning_path_studio_dialogs.dart';

class LearningPathStudioPanel extends StatefulWidget {
  const LearningPathStudioPanel({
    required this.catalog,
    required this.paths,
    required this.workspaceNodes,
    required this.onSave,
    required this.onDelete,
    this.initialDraft,
    this.draftIds,
    this.workspaceMode = LearningPathMode.simple,
    required this.onStart,
    this.onHighlightsChanged,
    this.onImport,
    this.onImportSave,
    this.onExport,
    this.onExportRemote,
    this.onShareClassroom,
    super.key,
  });

  final TranslationCatalog catalog;
  final List<AuthoredLearningPath> paths;
  final Set<String>? draftIds;
  final List<BlockNode> workspaceNodes;
  final LearningPathMode workspaceMode;
  final AuthoredLearningPath? initialDraft;
  final Future<void> Function(AuthoredLearningPath) onStart;
  final ValueChanged<Set<String>>? onHighlightsChanged;
  final Future<void> Function(AuthoredLearningPath path) onSave;
  final Future<void> Function(String id) onDelete;

  /// Selects and reads a bundle; it does not change the library.
  final Future<List<AuthoredLearningPath>> Function()? onImport;
  final Future<void> Function(List<AuthoredLearningPath> drafts)? onImportSave;
  final Future<void> Function(List<AuthoredLearningPath> paths)? onExport;
  final Future<void> Function(AuthoredLearningPath path)? onExportRemote;
  final ValueChanged<AuthoredLearningPath>? onShareClassroom;

  @override
  State<LearningPathStudioPanel> createState() =>
      _LearningPathStudioPanelState();
}

class _LearningPathStudioPanelState extends State<LearningPathStudioPanel> {
  late List<AuthoredLearningPath> _paths;
  Set<String>? _draftIds;
  AuthoredLearningPath? _editing;
  bool _libraryBusy = false;
  final _reviews = Expando<LearningPathReview>();

  TranslationCatalog get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    _paths = List.of(widget.paths);
    _draftIds = widget.draftIds?.toSet();
    _editing = widget.initialDraft;
  }

  @override
  void didUpdateWidget(covariant LearningPathStudioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.paths, oldWidget.paths) ||
        !setEquals(widget.draftIds, oldWidget.draftIds)) {
      _paths = List.of(widget.paths);
      _draftIds = widget.draftIds?.toSet();
    }
  }

  LearningPathReview _review(AuthoredLearningPath path) =>
      _reviews[path] ??= reviewLearningPath(path);

  @override
  Widget build(BuildContext context) {
    final editing = _editing;
    return Material(
      key: const ValueKey('workshop-creation-panel'),
      color: Theme.of(context).colorScheme.surface,
      child: IndexedStack(
        index: editing == null ? 0 : 1,
        sizing: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: editing != null,
            child: LearningPathStudioLibrary(
              catalog: catalog,
              paths: _paths,
              draftIds: _draftIds,
              busy: _libraryBusy,
              reviewFor: _review,
              onCreate: () => setState(() => _editing = _emptyPath()),
              onEdit: (path) => setState(() => _editing = path),
              onPreview: (path) =>
                  _runLibraryAction('previewFailed', () => _preview(path)),
              onDuplicate: (path) =>
                  _runLibraryAction('copyFailed', () => _duplicate(path)),
              onDelete: (path) =>
                  _runLibraryAction('deleteFailed', () => _delete(path)),
              onImport: widget.onImport == null
                  ? null
                  : () => _runLibraryAction('importFailed', _import),
              onExportCatalog: widget.onExport == null
                  ? null
                  : () => _runLibraryAction('exportFailed', _exportCatalog),
              onShareClassroom: widget.onShareClassroom == null
                  ? null
                  : (path) => _runLibraryAction(
                      'shareFailed',
                      () => _distribute(path, () async {
                        widget.onShareClassroom!(path);
                      }),
                    ),
              onExportDownload: widget.onExportRemote == null
                  ? null
                  : (path) => _runLibraryAction(
                      'exportFailed',
                      () =>
                          _distribute(path, () => widget.onExportRemote!(path)),
                    ),
              onCheck: (path) =>
                  _showWorkshopReview(context, catalog, path, _review(path)),
            ),
          ),
          if (editing != null)
            _LearningPathEditor(
              key: ValueKey(editing.id),
              catalog: catalog,
              initialPath: editing,
              workspaceNodes: widget.workspaceNodes,
              workspaceMode: widget.workspaceMode,
              onHighlightsChanged: widget.onHighlightsChanged,
              onCancel: () => setState(() => _editing = null),
              onSave: (next) async {
                await widget.onSave(next);
                if (!mounted) return;
                setState(() {
                  _recordDrafts([next]);
                  _editing = next;
                });
              },
              onPreview: (path) => _preview(path),
            ),
        ],
      ),
    );
  }

  AuthoredLearningPath _emptyPath() => AuthoredLearningPath(
    id: learningPathId('learning-path'),
    title: '',
    description: '',
    steps: const [],
  );

  void _recordDrafts(List<AuthoredLearningPath> drafts) {
    final ids = drafts.map((draft) => draft.id).toSet();
    _paths = [...drafts, ..._paths.where((path) => !ids.contains(path.id))];
    _draftIds?.addAll(ids);
  }

  Future<void> _saveNewDrafts(List<AuthoredLearningPath> drafts) async {
    final saveAll = widget.onImportSave;
    if (saveAll != null) {
      await saveAll(drafts);
      if (mounted) setState(() => _recordDrafts(drafts));
    } else {
      for (final draft in drafts) {
        await widget.onSave(draft);
        if (mounted) setState(() => _recordDrafts([draft]));
      }
    }
  }

  Future<void> _duplicate(AuthoredLearningPath path) async {
    final title = catalog.text('tutorial.studio.copyTitle', {
      'title': path.titleFor(catalog.locale),
    });
    final copy = copyLearningPath(path, title: title);
    await _saveNewDrafts([copy]);
    if (mounted) setState(() => _editing = copy);
  }

  Future<void> _delete(AuthoredLearningPath path) async {
    await widget.onDelete(path.id);
    if (!mounted) return;
    setState(() {
      // A draft created by an older Studio can shadow a bundled template.
      final stillPresent =
          widget.draftIds?.contains(path.id) == false &&
          widget.paths.any((item) => item.id == path.id && item != path);
      if (!stillPresent) _paths.removeWhere((item) => item.id == path.id);
      _draftIds?.remove(path.id);
    });
  }

  Future<void> _import() async {
    final paths = await widget.onImport!.call();
    if (!mounted || paths.isEmpty) return;
    final accepted = await _confirmWorkshopImport(context, catalog, paths);
    if (!mounted || !accepted) return;
    final drafts = paths.map(copyLearningPath).toList(growable: false);
    await _saveNewDrafts(drafts);
    if (mounted) {
      _showStudioMessage(context, catalog, 'imported', {
        'count': drafts.length,
      });
    }
  }

  Future<void> _exportCatalog() async {
    final selection = await _selectCatalogPaths(
      context,
      catalog,
      _paths,
      _review,
    );
    if (!mounted || selection == null) return;
    await widget.onExport!(selection);
  }

  Future<void> _preview(AuthoredLearningPath path) async {
    final review = _review(path);
    if (!review.canPreview) {
      await _showWorkshopReview(context, catalog, path, review);
      return;
    }
    await widget.onStart(path);
  }

  Future<void> _distribute(
    AuthoredLearningPath path,
    Future<void> Function() action,
  ) async {
    final review = _review(path);
    if (!review.canShare) {
      await _showWorkshopReview(context, catalog, path, review);
      return;
    }
    await action();
  }

  Future<void> _runLibraryAction(
    String failureKey,
    Future<void> Function() action,
  ) async {
    if (_libraryBusy) return;
    setState(() => _libraryBusy = true);
    try {
      await action();
    } catch (error, stack) {
      debugPrint('Workshop Studio ($failureKey): $error\n$stack');
      if (mounted) _showStudioMessage(context, catalog, failureKey);
    } finally {
      if (mounted) setState(() => _libraryBusy = false);
    }
  }
}

class _LearningPathEditor extends StatefulWidget {
  const _LearningPathEditor({
    required this.catalog,
    required this.initialPath,
    required this.workspaceNodes,
    required this.workspaceMode,
    required this.onHighlightsChanged,
    required this.onCancel,
    required this.onSave,
    required this.onPreview,
    super.key,
  });

  final TranslationCatalog catalog;
  final AuthoredLearningPath initialPath;
  final List<BlockNode> workspaceNodes;
  final LearningPathMode workspaceMode;
  final ValueChanged<Set<String>>? onHighlightsChanged;
  final VoidCallback onCancel;
  final Future<void> Function(AuthoredLearningPath path) onSave;
  final Future<void> Function(AuthoredLearningPath path) onPreview;

  @override
  State<_LearningPathEditor> createState() => _LearningPathEditorState();
}

class _LearningPathEditorState extends State<_LearningPathEditor> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final List<LearningPathStep> _steps;
  int? _editingStep;
  bool _saving = false;
  bool _saveFailed = false;
  bool _previewFailed = false;

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
    final editingStep = _editingStep;
    if (editingStep != null) {
      return _LearningPathStepEditor(
        key: ValueKey('step-editor-$editingStep'),
        catalog: catalog,
        workspaceNodes: widget.workspaceNodes,
        workspaceMode: widget.workspaceMode,
        stepNumber: editingStep + 1,
        initialStep: editingStep < _steps.length ? _steps[editingStep] : null,
        onHighlightsChanged: widget.onHighlightsChanged,
        onCancel: () {
          widget.onHighlightsChanged?.call({});
          setState(() => _editingStep = null);
        },
        onSave: (step) {
          widget.onHighlightsChanged?.call({});
          setState(() {
            if (editingStep == _steps.length) {
              _steps.add(step);
            } else {
              _steps[editingStep] = step;
            }
            _editingStep = null;
          });
        },
      );
    }
    final hasName = _title.text.trim().isNotEmpty;
    final canSave = !_saving && hasName;
    final message = _saveFailed
        ? 'tutorial.studio.saveFailed'
        : _previewFailed
        ? 'tutorial.studio.previewFailed'
        : !hasName
        ? 'tutorial.studio.needsTitle'
        : _steps.isEmpty
        ? 'tutorial.studio.needsStep'
        : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (canSave) _save(tryWorkshop: false);
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (canSave) _save(tryWorkshop: false);
        },
      },
      child: FocusScope(
        child: _buildForm(hasName: hasName, canSave: canSave, message: message),
      ),
    );
  }

  Widget _buildForm({
    required bool hasName,
    required bool canSave,
    required String? message,
  }) {
    return Column(
      children: [
        _StudioHeader(
          title: catalog.text('tutorial.studio.editorTitle'),
          subtitle: catalog.text('tutorial.studio.editorSubtitle'),
          onBack: _saving ? null : _leave,
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
                    onChanged: (_) => setState(() => _saveFailed = false),
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
                  TextButton.icon(
                    key: const ValueKey('learning-path-review'),
                    onPressed: _saving ? null : _checkDraft,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(catalog.text('tutorial.studio.checkWorkshop')),
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
                    color: _saveFailed || _previewFailed
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
                    onPressed: canSave && _steps.isNotEmpty
                        ? () => _save(tryWorkshop: true)
                        : null,
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

  void _openStep([int? index]) {
    setState(() => _editingStep = index ?? _steps.length);
  }

  Future<void> _checkDraft() async {
    final draft = _draft();
    final index = await _showWorkshopReview(
      context,
      catalog,
      draft,
      reviewLearningPath(draft),
      canEditSteps: true,
    );
    if (mounted && index != null) _openStep(index);
  }

  Future<void> _leave() async {
    final initial = widget.initialPath;
    final changed =
        _title.text.trim() != initial.title ||
        _description.text.trim() != initial.description ||
        !listEquals(_steps, initial.steps);
    if (changed && !await _confirmDiscard(context, catalog)) return;
    if (mounted) widget.onCancel();
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
    if (_saving || draft.title.isEmpty) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
      _previewFailed = false;
    });
    var saved = false;
    try {
      await widget.onSave(draft);
      saved = true;
      if (!mounted) return;
      if (tryWorkshop) {
        final review = reviewLearningPath(draft);
        if (review.canPreview) {
          await widget.onPreview(draft);
        } else {
          final index = await _showWorkshopReview(
            context,
            catalog,
            draft,
            review,
            canEditSteps: true,
          );
          if (mounted && index != null) _openStep(index);
        }
      } else {
        _showStudioMessage(context, catalog, 'draftSaved');
      }
    } catch (error, stack) {
      debugPrint('Workshop Studio (save): $error\n$stack');
      if (mounted) {
        setState(() {
          _saveFailed = !saved;
          _previewFailed = saved;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LearningPathStepEditor extends StatefulWidget {
  const _LearningPathStepEditor({
    required this.catalog,
    required this.workspaceNodes,
    required this.workspaceMode,
    required this.stepNumber,
    super.key,
    required this.onSave,
    required this.onCancel,
    this.onHighlightsChanged,
    this.initialStep,
  });

  final TranslationCatalog catalog;
  final List<BlockNode> workspaceNodes;
  final LearningPathMode workspaceMode;
  final int stepNumber;
  final LearningPathStep? initialStep;
  final ValueChanged<LearningPathStep> onSave;
  final VoidCallback onCancel;
  final ValueChanged<Set<String>>? onHighlightsChanged;

  @override
  State<_LearningPathStepEditor> createState() =>
      _LearningPathStepEditorState();
}

class _LearningPathStepEditorState extends State<_LearningPathStepEditor> {
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
  late final String _initialForm;
  bool _editingRule = false;
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
    _initialForm = _formSnapshot();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onHighlightsChanged?.call(
          _highlights.where(_isInteractionRef).toSet(),
        );
      }
    });
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

  String _formSnapshot() => jsonEncode([
    _title.text,
    _instruction.text,
    _hint.text,
    _calloutTitle.text,
    _calloutBody.text,
    [
      for (final node in _nodes)
        if (_selectedRefs.contains(node.ref)) node.toJson(),
    ],
    _callouts.map((callout) => callout.toJson()).toList(),
    _highlights.toList(),
    _requirements.map((rule) => rule.toJson()).toList(),
  ]);

  Future<void> _leaveStep() async {
    if ((_editingRule || _initialForm != _formSnapshot()) &&
        !await _confirmDiscard(context, catalog)) {
      return;
    }
    if (mounted) widget.onCancel();
  }

  void _selectNodes(List<LearningPathNodeTemplate> nodes) {
    final refs = <String>{};
    _nodes = [
      for (final node in nodes)
        if (node.ref.trim().isNotEmpty &&
            node.ref != _startNode?.ref &&
            refs.add(node.ref))
          node,
    ];
    _selectedRefs = refs;
    _targetRef = _nodes.firstOrNull?.ref;
  }

  void _toggleNode(LearningPathNodeTemplate node, bool selected) {
    setState(() {
      if (selected) {
        _selectedRefs.add(node.ref);
      } else {
        _selectedRefs.remove(node.ref);
      }
      widget.onHighlightsChanged?.call(
        _highlights.where(_isInteractionRef).toSet(),
      );
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
        !_editingRule &&
        _title.text.trim().isNotEmpty &&
        _instruction.text.trim().isNotEmpty;
    final canReplaceNodes = widget.workspaceNodes.any(
      (node) => node.type != BlockType.eventGreenFlag,
    );
    return Column(
      children: [
        _StudioHeader(
          title: catalog.text('tutorial.studio.stepEditor', {
            'number': widget.stepNumber,
          }),
          subtitle: catalog.text('tutorial.studio.stepHelp'),
          onBack: _leaveStep,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
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
                        onChanged: _editingRule
                            ? null
                            : (selected) => _toggleNode(node, selected == true),
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
              if (canReplaceNodes)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('learning-step-use-workspace'),
                    onPressed: _editingRule
                        ? null
                        : () => setState(() {
                            _selectNodes(_workspaceTemplates());
                            widget.onHighlightsChanged?.call(
                              _highlights.where(_isInteractionRef).toSet(),
                            );
                          }),
                    icon: const Icon(Icons.add_to_photos_outlined),
                    label: Text(
                      catalog.text('tutorial.studio.useWorkspaceNodes'),
                    ),
                  ),
                ),
              LearningPathInteractionEditor(
                catalog: catalog,
                onEditingChanged: (editing) =>
                    setState(() => _editingRule = editing),
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
                  widget.onHighlightsChanged?.call(
                    _highlights.where(_isInteractionRef).toSet(),
                  );
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
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _leaveStep,
                child: Text(catalog.text('tutorial.studio.cancel')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('learning-step-apply'),
                onPressed: canSave ? _save : null,
                child: Text(catalog.text('tutorial.studio.applyStep')),
              ),
            ],
          ),
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
    widget.onSave(
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
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;

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
