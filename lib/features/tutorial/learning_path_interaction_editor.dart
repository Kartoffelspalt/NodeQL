import 'package:flutter/material.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/localization/translation_catalog.dart';

import 'learning_path_authoring.dart';
import 'learning_path_interactions.dart';

class LearningPathInteractionEditor extends StatefulWidget {
  const LearningPathInteractionEditor({
    required this.catalog,
    required this.mode,
    required this.nodes,
    required this.nodeLabel,
    required this.highlights,
    required this.requirements,
    required this.onHighlight,
    required this.onRequirementsChanged,
    required this.onEditingChanged,
    super.key,
  });

  final TranslationCatalog catalog;
  final SqlAbstractionMode mode;
  final List<LearningPathNodeTemplate> nodes;
  final String Function(LearningPathNodeTemplate) nodeLabel;
  final Set<String> highlights;
  final List<LearningPathRequirement> requirements;
  final ValueChanged<String> onHighlight;
  final ValueChanged<List<LearningPathRequirement>> onRequirementsChanged;
  final ValueChanged<bool> onEditingChanged;

  @override
  State<LearningPathInteractionEditor> createState() =>
      _LearningPathInteractionEditorState();
}

class _LearningPathInteractionEditorState
    extends State<LearningPathInteractionEditor> {
  final _ruleFormKey = GlobalKey();
  int? _editingRule;
  TranslationCatalog get catalog => widget.catalog;

  void _editRule([int? index]) {
    setState(() => _editingRule = index ?? widget.requirements.length);
    widget.onEditingChanged(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _ruleFormKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.05,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  void _saveRule(LearningPathRequirement rule) {
    final index = _editingRule!;
    final next = List<LearningPathRequirement>.of(widget.requirements);
    if (index == next.length) {
      next.add(rule);
    } else {
      next[index] = rule;
    }
    widget.onRequirementsChanged(next);
    setState(() => _editingRule = null);
    widget.onEditingChanged(false);
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const ValueKey('learning-step-interactions'),
    tilePadding: EdgeInsets.zero,
    title: Text(catalog.text('tutorial.action.title')),
    subtitle: Text(
      catalog.text('tutorial.action.summary', {
        'rules': widget.requirements.length,
        'highlights': widget.highlights.length,
      }),
    ),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.nodes.isNotEmpty) ...[
        Text(catalog.text('tutorial.action.highlight')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final node in widget.nodes)
              FilterChip(
                label: Text(
                  widget.nodeLabel(node),
                  overflow: TextOverflow.ellipsis,
                ),
                selected: widget.highlights.contains(node.ref),
                onSelected: (_) => widget.onHighlight(node.ref),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      Text(catalog.text('tutorial.action.waitHelp')),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('workshop-action-add'),
          onPressed: _editingRule != null || widget.requirements.length >= 16
              ? null
              : () => _editRule(),
          icon: const Icon(Icons.add),
          label: Text(catalog.text('tutorial.action.add')),
        ),
      ),
      if (_editingRule case final index?)
        Padding(
          key: _ruleFormKey,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _ActionEditor(
            key: ValueKey(index),
            catalog: catalog,
            mode: widget.mode,
            nodes: widget.nodes,
            nodeLabel: widget.nodeLabel,
            initial: index < widget.requirements.length
                ? widget.requirements[index]
                : null,
            onSave: _saveRule,
            onCancel: () {
              setState(() => _editingRule = null);
              widget.onEditingChanged(false);
            },
          ),
        ),
      for (var index = 0; index < widget.requirements.length; index++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            learningPathRequirementLabel(
              catalog,
              widget.requirements[index],
              (ref) => widget.nodeLabel(
                widget.nodes.firstWhere((node) => node.ref == ref),
              ),
            ),
          ),
          subtitle: widget.requirements[index].value == null
              ? null
              : Text(
                  catalog.text('tutorial.action.expectedSummary', {
                    'value': widget.requirements[index].value,
                  }),
                ),
          onTap: _editingRule == null ? () => _editRule(index) : null,
          trailing: IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            icon: const Icon(Icons.close),
            onPressed: _editingRule != null
                ? null
                : () => widget.onRequirementsChanged(
                    List<LearningPathRequirement>.of(widget.requirements)
                      ..removeAt(index),
                  ),
          ),
        ),
    ],
  );
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({
    required this.catalog,
    required this.mode,
    required this.nodes,
    required this.nodeLabel,
    required this.onSave,
    required this.onCancel,
    super.key,
    this.initial,
  });

  final TranslationCatalog catalog;
  final SqlAbstractionMode mode;
  final List<LearningPathNodeTemplate> nodes;
  final String Function(LearningPathNodeTemplate) nodeLabel;
  final LearningPathRequirement? initial;
  final ValueChanged<LearningPathRequirement> onSave;
  final VoidCallback onCancel;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late LearningPathAction _action;
  String? _nodeRef;
  String? _otherRef;
  String? _input;
  late final TextEditingController _value;

  TranslationCatalog get catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _action = initial?.action ?? LearningPathAction.enterInput;
    if (initial == null && !widget.nodes.any(_canTarget)) {
      _action = LearningPathAction.selectNode;
      if (!widget.nodes.any(_canTarget)) _action = LearningPathAction.runQuery;
    }
    _nodeRef = initial?.nodeRef;
    _otherRef = initial?.otherRef;
    _input = initial?.input;
    _value = TextEditingController(text: initial?.value);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Iterable<String> _fields(LearningPathNodeTemplate node) {
    final slots = <String, String>{
      for (final match in RegExp(r'\[([^\]]+)\]|\{([^}]+)\}').allMatches(
        sqlLabelFor(node.type, widget.mode, node.defaults, catalog.locale),
      ))
        sqlInputKey((match[1] ?? match[2])!): match[0]!,
    };
    return slots.entries
        .where(
          (slot) =>
              RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(slot.key) &&
              (_action == LearningPathAction.attachReporter
                  ? slotAcceptsReporter(slot.value, slot.key)
                  : !requiresReporterInput(node.type, slot.key)),
        )
        .map((entry) => entry.key);
  }

  bool _canTarget(LearningPathNodeTemplate node) => switch (_action) {
    LearningPathAction.enterInput ||
    LearningPathAction.attachReporter => _fields(node).isNotEmpty,
    LearningPathAction.connectNodes ||
    LearningPathAction.selectNode => !isReporterType(node.type),
    LearningPathAction.linkColumns => acceptsColumnSource(node.type),
    LearningPathAction.runQuery => false,
  };

  bool _canUseAsOther(LearningPathNodeTemplate node) =>
      node.ref != _nodeRef &&
      switch (_action) {
        LearningPathAction.attachReporter =>
          _input == 'aggregate'
              ? slotAcceptsReporterType('aggregate', 'aggregate', node.type)
              : isReporterType(node.type),
        LearningPathAction.linkColumns => providesColumnSource(node.type),
        LearningPathAction.connectNodes => !isReporterType(node.type),
        _ => false,
      };

  Widget _select<T>({
    required String id,
    required String label,
    required T? value,
    required Iterable<T> options,
    required String Function(T) display,
    required ValueChanged<T?> onChanged,
  }) => DropdownButtonFormField<T>(
    key: ValueKey(id),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final option in options)
        DropdownMenuItem(
          value: option,
          child: Text(display(option), overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final targets = widget.nodes.where(_canTarget);
    final target = targets.where((node) => node.ref == _nodeRef).firstOrNull;
    final fields = target == null ? const <String>[] : _fields(target);
    final others = widget.nodes.where(_canUseAsOther);
    final canSave =
        (!_action.needsNode || target != null) &&
        (!_action.needsInput || fields.contains(_input)) &&
        (!_action.needsOtherNode ||
            others.any((node) => node.ref == _otherRef));
    String displayNode(String ref) =>
        widget.nodeLabel(widget.nodes.firstWhere((node) => node.ref == ref));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            catalog.text(
              widget.initial == null
                  ? 'tutorial.action.add'
                  : 'tutorial.action.edit',
            ),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 14),
          _select<LearningPathAction>(
            id: 'workshop-action-kind',
            label: catalog.text('tutorial.action.kind'),
            value: _action,
            options: LearningPathAction.values.where(
              (action) => !action.needsNode || widget.nodes.isNotEmpty,
            ),
            display: (action) => catalog.text('tutorial.action.${action.name}'),
            onChanged: (action) => setState(() {
              if (action == null) return;
              _action = action;
              _nodeRef = null;
              _otherRef = null;
              _input = null;
            }),
          ),
          if (_action.needsNode) ...[
            const SizedBox(height: 12),
            if (targets.isEmpty)
              Text(catalog.text('tutorial.action.noTargets'))
            else
              _select<String>(
                id: 'workshop-action-node-${_action.name}',
                label: catalog.text('tutorial.action.node'),
                value: target?.ref,
                options: targets.map((node) => node.ref),
                display: displayNode,
                onChanged: (node) => setState(() {
                  _nodeRef = node;
                  _input = null;
                  _otherRef = null;
                }),
              ),
          ],
          if (_action.needsInput && target != null) ...[
            const SizedBox(height: 12),
            _select<String>(
              id: 'workshop-action-input-${_action.name}-${target.ref}',
              label: catalog.text('tutorial.action.input'),
              value: fields.contains(_input) ? _input : null,
              options: fields,
              display: (input) => learningPathInputLabel(catalog, input),
              onChanged: (input) => setState(() {
                _input = input;
                _otherRef = null;
              }),
            ),
          ],
          if (_action.needsOtherNode &&
              target != null &&
              (!_action.needsInput || _input != null)) ...[
            const SizedBox(height: 12),
            if (others.isEmpty)
              Text(catalog.text('tutorial.action.noTargets'))
            else
              _select<String>(
                id: 'workshop-action-other-${_action.name}-${target.ref}-$_input',
                label: catalog.text(
                  _action == LearningPathAction.attachReporter
                      ? 'tutorial.action.reporter'
                      : 'tutorial.action.source',
                ),
                value: others.any((node) => node.ref == _otherRef)
                    ? _otherRef
                    : null,
                options: others.map((node) => node.ref),
                display: displayNode,
                onChanged: (node) => setState(() => _otherRef = node),
              ),
          ],
          if (_action == LearningPathAction.enterInput && _input != null) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('workshop-action-value'),
              controller: _value,
              maxLength: 512,
              decoration: InputDecoration(
                labelText: catalog.text('tutorial.action.expected'),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: Text(catalog.text('tutorial.studio.cancel')),
              ),
              FilledButton(
                key: const ValueKey('workshop-action-apply'),
                onPressed: canSave
                    ? () => widget.onSave(
                        LearningPathRequirement(
                          action: _action,
                          nodeRef: _action.needsNode ? _nodeRef : null,
                          otherRef: _action.needsOtherNode ? _otherRef : null,
                          input: _action.needsInput ? _input : null,
                          value:
                              _action == LearningPathAction.enterInput &&
                                  _value.text.trim().isNotEmpty
                              ? _value.text.trim()
                              : null,
                        ),
                      )
                    : null,
                child: Text(catalog.text('tutorial.action.apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
