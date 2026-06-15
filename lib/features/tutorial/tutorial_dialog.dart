import 'package:flutter/material.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/scratch_style.dart';
import 'package:nodeql/features/workbench/presentation/widgets/block_shape_painter.dart';
import 'package:nodeql/localization/translation_catalog.dart';

class TutorialDialog extends StatefulWidget {
  const TutorialDialog({
    required this.catalog,
    required this.onComplete,
    super.key,
  });

  final TranslationCatalog catalog;
  final Future<void> Function() onComplete;

  @override
  State<TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<TutorialDialog> {
  static const _stepCount = 7;
  int _step = 0;
  int _furthestStep = 0;
  final Set<int> _solvedSteps = <int>{};
  final Map<int, int> _answers = <int, int>{};

  TranslationCatalog get catalog => widget.catalog;
  bool get _hasChallenge => _correctAnswer(_step) != null;
  bool get _canContinue => !_hasChallenge || _solvedSteps.contains(_step);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 820;
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Column(
              children: [
                _TutorialHeader(
                  catalog: catalog,
                  step: _step,
                  stepCount: _stepCount,
                  onSkip: _finish,
                ),
                LinearProgressIndicator(
                  value: (_step + 1) / _stepCount,
                  minHeight: 4,
                  backgroundColor: workbenchColors.border,
                ),
                Expanded(
                  child: compact
                      ? _buildCompactContent()
                      : Row(
                          children: [
                            _StepRail(
                              catalog: catalog,
                              currentStep: _step,
                              furthestStep: _furthestStep,
                              solvedSteps: _solvedSteps,
                              onStep: _goToStep,
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: _buildStepContent()),
                          ],
                        ),
                ),
                _TutorialFooter(
                  catalog: catalog,
                  step: _step,
                  stepCount: _stepCount,
                  canContinue: _canContinue,
                  onBack: _step == 0 ? null : () => _goToStep(_step - 1),
                  onNext: _next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            catalog.text('tutorial.progress', {
              'current': _step + 1,
              'total': _stepCount,
            }),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(child: _buildStepContent()),
      ],
    );
  }

  Widget _buildStepContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            catalog.text('tutorial.step.${_step + 1}.eyebrow'),
            style: const TextStyle(
              color: Color(0xFF60A5FA),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            catalog.text('tutorial.step.${_step + 1}.title'),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            catalog.text('tutorial.step.${_step + 1}.body'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _TutorialVisual(step: _step, catalog: catalog),
          if (_hasChallenge) ...[const SizedBox(height: 24), _buildChallenge()],
        ],
      ),
    );
  }

  Widget _buildChallenge() {
    final answer = _answers[_step];
    final correct = _correctAnswer(_step)!;
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: workbenchColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: workbenchColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_alt_outlined,
                color: Color(0xFF38BDF8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  catalog.text('tutorial.step.${_step + 1}.question'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var option = 0; option < 3; option++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                key: ValueKey('tutorial-answer-$_step-$option'),
                onPressed: () => _selectAnswer(option),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  side: BorderSide(
                    color: answer == option
                        ? (option == correct
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444))
                        : workbenchColors.border,
                  ),
                  backgroundColor: answer == option
                      ? (option == correct
                            ? const Color(0x1922C55E)
                            : const Color(0x19EF4444))
                      : null,
                ),
                child: Text(
                  catalog.text(
                    'tutorial.step.${_step + 1}.answer.${option + 1}',
                  ),
                ),
              ),
            ),
          if (answer != null)
            Text(
              catalog.text(
                answer == correct
                    ? 'tutorial.answer.correct'
                    : 'tutorial.answer.retry',
              ),
              style: TextStyle(
                color: answer == correct
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFCA5A5),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  int? _correctAnswer(int step) => switch (step) {
    1 => 1,
    2 => 0,
    3 => 2,
    4 => 1,
    5 => 0,
    _ => null,
  };

  void _selectAnswer(int answer) {
    setState(() {
      _answers[_step] = answer;
      if (answer == _correctAnswer(_step)) {
        _solvedSteps.add(_step);
      }
    });
  }

  void _goToStep(int step) {
    setState(() => _step = step.clamp(0, _stepCount - 1));
  }

  Future<void> _next() async {
    if (!_canContinue) return;
    if (_step == _stepCount - 1) {
      await _finish();
      return;
    }
    if (_step + 1 > _furthestStep) _furthestStep = _step + 1;
    _goToStep(_step + 1);
  }

  Future<void> _finish() async {
    await widget.onComplete();
    if (mounted) Navigator.of(context).pop();
  }
}

class _TutorialHeader extends StatelessWidget {
  const _TutorialHeader({
    required this.catalog,
    required this.step,
    required this.stepCount,
    required this.onSkip,
  });

  final TranslationCatalog catalog;
  final int step;
  final int stepCount;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      color: workbenchColors.topBar,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_tree_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              catalog.text('tutorial.title'),
              style: TextStyle(
                color: workbenchColors.topBarForeground,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            catalog.text('tutorial.progress', {
              'current': step + 1,
              'total': stepCount,
            }),
            style: TextStyle(color: workbenchColors.muted),
          ),
          const SizedBox(width: 14),
          TextButton(
            key: const ValueKey('tutorial-skip'),
            onPressed: onSkip,
            child: Text(catalog.text('tutorial.skip')),
          ),
        ],
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.catalog,
    required this.currentStep,
    required this.furthestStep,
    required this.solvedSteps,
    required this.onStep,
  });

  final TranslationCatalog catalog;
  final int currentStep;
  final int furthestStep;
  final Set<int> solvedSteps;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 235,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: 7,
        itemBuilder: (context, index) {
          final active = index == currentStep;
          final complete = index < currentStep || solvedSteps.contains(index);
          final unlocked = index <= furthestStep;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              selected: active,
              selectedTileColor: colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: CircleAvatar(
                radius: 15,
                backgroundColor: active
                    ? colorScheme.primary
                    : workbenchColors.border,
                child: complete
                    ? Icon(
                        Icons.check,
                        size: 17,
                        color: active
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: active
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              title: Text(
                catalog.text('tutorial.step.${index + 1}.nav'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: unlocked ? null : workbenchColors.muted,
                ),
              ),
              enabled: unlocked,
              onTap: unlocked ? () => onStep(index) : null,
            ),
          );
        },
      ),
    );
  }
}

class _TutorialFooter extends StatelessWidget {
  const _TutorialFooter({
    required this.catalog,
    required this.step,
    required this.stepCount,
    required this.canContinue,
    required this.onBack,
    required this.onNext,
  });

  final TranslationCatalog catalog;
  final int step;
  final int stepCount;
  final bool canContinue;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: workbenchColors.panel,
        border: Border(top: BorderSide(color: workbenchColors.border)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('tutorial-back'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(catalog.text('tutorial.back')),
          ),
          Expanded(
            child: canContinue
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      catalog.text('tutorial.solveFirst'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: workbenchColors.muted),
                    ),
                  ),
          ),
          FilledButton.icon(
            key: const ValueKey('tutorial-next'),
            onPressed: canContinue ? onNext : null,
            icon: Icon(
              step == stepCount - 1 ? Icons.rocket_launch : Icons.arrow_forward,
            ),
            label: Text(
              catalog.text(
                step == stepCount - 1 ? 'tutorial.finish' : 'tutorial.next',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialVisual extends StatelessWidget {
  const _TutorialVisual({required this.step, required this.catalog});

  final int step;
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 210),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [workbenchColors.panelElevated, workbenchColors.panel],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: workbenchColors.border),
      ),
      child: switch (step) {
        0 => _WelcomeVisual(catalog: catalog),
        1 => _InterfaceVisual(catalog: catalog),
        2 => _QueryVisual(catalog: catalog),
        3 => _ConnectionVisual(catalog: catalog),
        4 => _RunVisual(catalog: catalog),
        5 => _PluginVisual(catalog: catalog),
        _ => _ReadyVisual(catalog: catalog),
      },
    );
  }
}

class _WelcomeVisual extends StatelessWidget {
  const _WelcomeVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        alignment: WrapAlignment.center,
        children: [
          _FeatureBadge(
            icon: Icons.extension_outlined,
            color: ScratchPalette.sqlQuery,
            label: catalog.text('tutorial.visual.blocks'),
          ),
          _FeatureBadge(
            icon: Icons.storage_outlined,
            color: ScratchPalette.sqlSource,
            label: catalog.text('tutorial.visual.database'),
          ),
          _FeatureBadge(
            icon: Icons.school_outlined,
            color: ScratchPalette.sqlJoin,
            label: catalog.text('tutorial.visual.learn'),
          ),
        ],
      ),
    );
  }
}

class _InterfaceVisual extends StatelessWidget {
  const _InterfaceVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final colors = NodeQlWorkbenchColors.of(context);
    return Row(
      children: [
        _PanePreview(
          flex: 2,
          icon: Icons.view_sidebar_outlined,
          label: catalog.text('tutorial.visual.palette'),
          color: colors.panelElevated,
        ),
        const SizedBox(width: 10),
        _PanePreview(
          flex: 4,
          icon: Icons.account_tree_outlined,
          label: catalog.text('tutorial.visual.workspace'),
          color: colors.workspace,
        ),
        const SizedBox(width: 10),
        _PanePreview(
          flex: 3,
          icon: Icons.terminal,
          label: catalog.text('tutorial.visual.output'),
          color: colors.panel,
        ),
      ],
    );
  }
}

class _QueryVisual extends StatelessWidget {
  const _QueryVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          children: [
            _block(
              EventBlock(id: 'tutorial-event', position: Offset.zero),
              ScratchPalette.events,
              catalog.text('tutorial.visual.execute'),
              250,
              58,
            ),
            _block(
              OperatorBlock(
                id: 'tutorial-select',
                position: Offset.zero,
                operatorType: BlockType.sqlSelect,
              ),
              ScratchPalette.sqlQuery,
              'SELECT name, city',
              250,
              56,
            ),
            _block(
              OperatorBlock(
                id: 'tutorial-from',
                position: Offset.zero,
                operatorType: BlockType.sqlFrom,
              ),
              ScratchPalette.sqlSource,
              'FROM customers',
              250,
              50,
            ),
            _block(
              MotionBlock(
                id: 'tutorial-where',
                position: Offset.zero,
                motionType: BlockType.sqlWhere,
              ),
              ScratchPalette.sqlFilter,
              'WHERE active = 1',
              250,
              50,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionVisual extends StatelessWidget {
  const _ConnectionVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _block(
          OperatorBlock(
            id: 'tutorial-connect-select',
            position: Offset.zero,
            operatorType: BlockType.sqlSelect,
          ),
          ScratchPalette.sqlQuery,
          'SELECT *',
          190,
          56,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 42,
            color: Color(0xFF60A5FA),
          ),
        ),
        Column(
          children: [
            const Icon(Icons.vertical_align_center, color: Color(0xFF4ADE80)),
            const SizedBox(height: 4),
            _block(
              OperatorBlock(
                id: 'tutorial-connect-from',
                position: Offset.zero,
                operatorType: BlockType.sqlFrom,
              ),
              ScratchPalette.sqlSource,
              'FROM orders',
              190,
              50,
            ),
          ],
        ),
      ],
    );
  }
}

class _RunVisual extends StatelessWidget {
  const _RunVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow),
                label: Text(catalog.text('toolbar.runSql')),
              ),
              const SizedBox(height: 14),
              Text(
                catalog.text('tutorial.visual.runHint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: workbenchColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: workbenchColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: workbenchColors.border),
            ),
            child: Text(
              'SELECT name, city\nFROM customers\nWHERE active = 1;',
              style: TextStyle(
                color: workbenchColors.sqlText,
                fontFamily: 'monospace',
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PluginVisual extends StatelessWidget {
  const _PluginVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final statement = OperatorBlock(
      id: 'tutorial-plugin-statement',
      position: Offset.zero,
      operatorType: BlockType.sqlSelect,
      inputs: const {
        r'$nodeqlPluginBlock': 'sample.statement',
        r'$nodeqlPluginShape': 'statement',
      },
    );
    final value = OperatorBlock(
      id: 'tutorial-plugin-value',
      position: Offset.zero,
      operatorType: BlockType.sqlColumn,
      inputs: const {
        r'$nodeqlPluginBlock': 'sample.value',
        r'$nodeqlPluginShape': 'value',
      },
    );
    final container = ControlBlock(
      id: 'tutorial-plugin-container',
      position: Offset.zero,
      controlType: BlockType.sqlLoop,
      inputs: const {
        r'$nodeqlPluginBlock': 'sample.container',
        r'$nodeqlPluginShape': 'container',
      },
    );
    return Center(
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _block(
            statement,
            ScratchPalette.myBlocks,
            catalog.text('tutorial.visual.pluginStatement'),
            210,
            56,
            pluginShape: 'statement',
          ),
          _block(
            value,
            ScratchPalette.sqlExpression,
            catalog.text('tutorial.visual.pluginValue'),
            180,
            46,
            pluginShape: 'value',
          ),
          _block(
            container,
            ScratchPalette.control,
            catalog.text('tutorial.visual.pluginContainer'),
            210,
            112,
            pluginShape: 'container',
          ),
        ],
      ),
    );
  }
}

class _ReadyVisual extends StatelessWidget {
  const _ReadyVisual({required this.catalog});
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 76,
            color: Color(0xFF22C55E),
          ),
          const SizedBox(height: 14),
          Text(
            catalog.text('tutorial.visual.ready'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: color),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PanePreview extends StatelessWidget {
  const _PanePreview({
    required this.flex,
    required this.icon,
    required this.label,
    required this.color,
  });

  final int flex;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Expanded(
      flex: flex,
      child: Container(
        height: 166,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: workbenchColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: colorScheme.onSurface),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _block(
  BlockNode node,
  Color color,
  String label,
  double width,
  double height, {
  String? pluginShape,
}) {
  return BlockShape(
    node: node,
    color: color,
    width: width,
    height: height,
    label: label,
    pluginShape: pluginShape,
  );
}
