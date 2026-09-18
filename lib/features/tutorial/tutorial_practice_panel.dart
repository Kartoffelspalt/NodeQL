import 'package:flutter/material.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/tutorial/tutorial_practice.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/localization/translation_catalog.dart';

class TutorialPracticePanel extends StatelessWidget {
  const TutorialPracticePanel({
    required this.catalog,
    required this.session,
    required this.definition,
    required this.result,
    required this.abstractionMode,
    required this.localeCode,
    required this.liveSql,
    required this.onCheck,
    required this.onHint,
    required this.onClose,
    super.key,
  });

  final TranslationCatalog catalog;
  final TutorialPracticeSession session;
  final TutorialPracticeDefinition definition;
  final TutorialPracticeResult result;
  final SqlAbstractionMode abstractionMode;
  final String localeCode;
  final String liveSql;
  final VoidCallback onCheck;
  final VoidCallback onHint;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    final stepKey = definition.stepKey(session.stepIndex);
    final maxHeight = (MediaQuery.sizeOf(context).height * .48).clamp(
      280.0,
      420.0,
    );
    return Material(
      key: const ValueKey('tutorial-practice-panel'),
      color: session.completed
          ? Color.alphaBlend(const Color(0x2422C55E), colors.panelElevated)
          : colors.panelElevated,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: session.completed
                  ? const Color(0xFF22C55E)
                  : colors.border,
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final copy = _PracticeCopy(
                catalog: catalog,
                session: session,
                definition: definition,
                result: result,
                abstractionMode: abstractionMode,
                localeCode: localeCode,
                stepKey: stepKey,
                liveSql: liveSql,
              );
              final actions = _PracticeActions(
                catalog: catalog,
                session: session,
                definition: definition,
                result: result,
                onCheck: onCheck,
                onHint: onHint,
                onClose: onClose,
              );
              if (constraints.maxWidth < 1000) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        child: copy,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: colors.panelElevated,
                        border: Border(top: BorderSide(color: colors.border)),
                      ),
                      child: actions,
                    ),
                  ],
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PracticeIcon(completed: session.completed),
                    const SizedBox(width: 14),
                    Expanded(child: copy),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PracticeIcon extends StatelessWidget {
  const _PracticeIcon({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        completed ? Icons.check : Icons.account_tree_outlined,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}

class _PracticeCopy extends StatelessWidget {
  const _PracticeCopy({
    required this.catalog,
    required this.session,
    required this.definition,
    required this.result,
    required this.abstractionMode,
    required this.localeCode,
    required this.stepKey,
    required this.liveSql,
  });

  final TranslationCatalog catalog;
  final TutorialPracticeSession session;
  final TutorialPracticeDefinition definition;
  final TutorialPracticeResult result;
  final SqlAbstractionMode abstractionMode;
  final String localeCode;
  final String stepKey;
  final String liveSql;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    final modeKey = abstractionMode == SqlAbstractionMode.simple
        ? 'tutorial.practice.mode.simple'
        : 'tutorial.practice.mode.advanced';
    TutorialPracticeCheck? nextCheck;
    for (final entry in result.outcomes.entries) {
      if (!entry.value) {
        nextCheck = entry.key;
        break;
      }
    }
    final progress = result.totalCount == 0
        ? 0.0
        : result.completedCount / result.totalCount;
    final step = definition.steps[session.stepIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              catalog.text('$stepKey.title'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            _InfoChip(
              icon: abstractionMode == SqlAbstractionMode.simple
                  ? Icons.auto_awesome_outlined
                  : Icons.code,
              label: catalog.text(modeKey),
            ),
            _InfoChip(
              icon: Icons.flag_outlined,
              label: catalog.text('tutorial.practice.stepProgress', {
                'current': session.stepIndex + 1,
                'total': definition.stepCount,
              }),
            ),
            _InfoChip(
              icon: Icons.schedule_outlined,
              label: catalog.text('tutorial.practice.estimatedTime', {
                'minutes': step.estimatedMinutes,
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  key: const ValueKey('tutorial-practice-progress'),
                  value: progress,
                  minHeight: 7,
                  backgroundColor: colors.panel,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              catalog.text('tutorial.practice.requirements', {
                'done': result.completedCount,
                'total': result.totalCount,
              }),
              style: TextStyle(
                color: colors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          session.completed
              ? catalog.text('tutorial.practice.success')
              : catalog.text('$stepKey.instruction'),
          style: TextStyle(color: colors.muted, height: 1.35),
        ),
        if (!session.completed) ...[
          const SizedBox(height: 5),
          Text(
            catalog.text(
              abstractionMode == SqlAbstractionMode.simple
                  ? 'tutorial.practice.modeHelp.simple'
                  : 'tutorial.practice.modeHelp.advanced',
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (step.focusNodes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _NodeLesson(
            catalog: catalog,
            stepKey: stepKey,
            nodeTypes: step.focusNodes,
            localeCode: localeCode,
          ),
        ],
        if (nextCheck != null && !session.completed) ...[
          const SizedBox(height: 9),
          Container(
            key: const ValueKey('tutorial-practice-next-requirement'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .45),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    catalog.text('tutorial.practice.nextRequirement', {
                      'requirement': catalog.text(
                        'tutorial.practice.check.${nextCheck.name}',
                      ),
                    }),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (session.showHint && !session.completed) ...[
          const SizedBox(height: 8),
          Text(
            catalog.text('$stepKey.hint'),
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final entry in result.outcomes.entries)
              _CheckChip(
                complete: entry.value,
                label: catalog.text(
                  'tutorial.practice.check.${entry.key.name}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _SyntaxPreview(
          catalog: catalog,
          example: catalog.text('$stepKey.example'),
          liveSql: liveSql,
        ),
        if (session.attempted && !result.complete) ...[
          const SizedBox(height: 8),
          Text(
            catalog.text('tutorial.practice.incomplete'),
            style: const TextStyle(
              color: Color(0xFFF87171),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _NodeLesson extends StatelessWidget {
  const _NodeLesson({
    required this.catalog,
    required this.stepKey,
    required this.nodeTypes,
    required this.localeCode,
  });

  final TranslationCatalog catalog;
  final String stepKey;
  final List<BlockType> nodeTypes;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.school_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Text(
                catalog.text('tutorial.practice.nodeFocus'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            catalog.text('$stepKey.concept'),
            style: TextStyle(color: colors.muted, height: 1.35),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in nodeTypes)
                _NodeExplanationCard(
                  catalog: catalog,
                  type: type,
                  localeCode: localeCode,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NodeExplanationCard extends StatelessWidget {
  const _NodeExplanationCard({
    required this.catalog,
    required this.type,
    required this.localeCode,
  });

  final TranslationCatalog catalog;
  final BlockType type;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    final simpleLabel = sqlLabelFor(
      type,
      SqlAbstractionMode.simple,
      const <String, dynamic>{},
      localeCode,
    );
    final advancedLabel = sqlLabelFor(
      type,
      SqlAbstractionMode.advanced,
      const <String, dynamic>{},
      localeCode,
    );
    return Container(
      width: 290,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.panelElevated,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            catalog.text('tutorial.practice.node.${type.name}.title'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            catalog.text('tutorial.practice.node.${type.name}.body'),
            style: TextStyle(color: colors.muted, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 8),
          _ModeLabel(
            title: catalog.text('tutorial.practice.label.simple'),
            value: simpleLabel,
            color: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 5),
          _ModeLabel(
            title: catalog.text('tutorial.practice.label.advanced'),
            value: advancedLabel,
            color: const Color(0xFF60A5FA),
          ),
        ],
      ),
    );
  }
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(top: 4),
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$title: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: value.replaceAll('\n', ' '),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 11, height: 1.3),
        ),
      ),
    ],
  );
}

class _SyntaxPreview extends StatelessWidget {
  const _SyntaxPreview({
    required this.catalog,
    required this.example,
    required this.liveSql,
  });

  final TranslationCatalog catalog;
  final String example;
  final String liveSql;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _SyntaxColumn(
            label: catalog.text('tutorial.practice.syntaxGoal'),
            value: example,
          ),
          _SyntaxColumn(
            label: catalog.text('tutorial.practice.syntaxLive'),
            value: liveSql.trim().isEmpty
                ? catalog.text('tutorial.practice.syntaxEmpty')
                : liveSql.trim(),
          ),
        ],
      ),
    );
  }
}

class _SyntaxColumn extends StatelessWidget {
  const _SyntaxColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 210, maxWidth: 420),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        SelectableText(
          value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    ),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.complete, required this.label});

  final bool complete;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: complete ? const Color(0x2022C55E) : colors.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: complete ? const Color(0xFF22C55E) : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            complete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 15,
            color: complete ? const Color(0xFF22C55E) : colors.muted,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PracticeActions extends StatelessWidget {
  const _PracticeActions({
    required this.catalog,
    required this.session,
    required this.definition,
    required this.result,
    required this.onCheck,
    required this.onHint,
    required this.onClose,
  });

  final TranslationCatalog catalog;
  final TutorialPracticeSession session;
  final TutorialPracticeDefinition definition;
  final TutorialPracticeResult result;
  final VoidCallback onCheck;
  final VoidCallback onHint;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.end,
    children: [
      if (!session.completed) ...[
        if (!session.showHint)
          OutlinedButton.icon(
            key: const ValueKey('tutorial-practice-hint'),
            onPressed: onHint,
            icon: const Icon(Icons.lightbulb_outline),
            label: Text(catalog.text('tutorial.practice.hint')),
          ),
        FilledButton.icon(
          key: const ValueKey('tutorial-practice-check'),
          onPressed: onCheck,
          icon: Icon(result.complete ? Icons.arrow_forward : Icons.task_alt),
          label: Text(
            result.complete
                ? catalog.text(
                    session.stepIndex == definition.stepCount - 1
                        ? 'tutorial.practice.finish'
                        : 'tutorial.practice.nextMission',
                  )
                : catalog.text('tutorial.practice.checkNodes'),
          ),
        ),
      ],
      IconButton(
        key: const ValueKey('tutorial-practice-close'),
        onPressed: onClose,
        tooltip: catalog.text('tutorial.practice.close'),
        icon: const Icon(Icons.close),
      ),
    ],
  );
}
