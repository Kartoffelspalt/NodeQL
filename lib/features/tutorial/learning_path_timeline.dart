import 'package:flutter/material.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/localization/translation_catalog.dart';

class LearningPathTimelinePanel extends StatelessWidget {
  const LearningPathTimelinePanel({
    required this.catalog,
    required this.path,
    required this.stepIndex,
    required this.onStep,
    required this.onClose,
    super.key,
  });

  final TranslationCatalog catalog;
  final AuthoredLearningPath path;
  final int stepIndex;
  final ValueChanged<int> onStep;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final step = path.steps[stepIndex];
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('learning-path-timeline-panel'),
      color: colorScheme.surfaceContainerHigh,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.timeline_rounded,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    step.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(step.instruction),
                  if (step.hint.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      step.hint,
                      style: TextStyle(
                        color: colorScheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 11),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var index = 0; index < path.steps.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ActionChip(
                              key: ValueKey('learning-path-step-$index'),
                              avatar: CircleAvatar(child: Text('${index + 1}')),
                              label: Text(path.steps[index].title),
                              backgroundColor: index == stepIndex
                                  ? colorScheme.primaryContainer
                                  : null,
                              onPressed: () => onStep(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    IconButton.outlined(
                      tooltip: catalog.text('tutorial.studio.previous'),
                      onPressed: stepIndex == 0
                          ? null
                          : () => onStep(stepIndex - 1),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    FilledButton.icon(
                      onPressed: stepIndex == path.steps.length - 1
                          ? onClose
                          : () => onStep(stepIndex + 1),
                      icon: Icon(
                        stepIndex == path.steps.length - 1
                            ? Icons.check
                            : Icons.arrow_forward,
                      ),
                      label: Text(
                        catalog.text(
                          stepIndex == path.steps.length - 1
                              ? 'tutorial.studio.finish'
                              : 'tutorial.studio.next',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: catalog.text('tutorial.studio.closePath'),
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  catalog.text('tutorial.studio.stepProgress', {
                    'current': stepIndex + 1,
                    'total': path.steps.length,
                  }),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
