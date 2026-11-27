import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nodeql/localization/translation_catalog.dart';

/// Stable IDs shared by exported Onboarding Studio files and the NodeQL UI.
enum OnboardingTarget {
  nodePalette,
  workspace,
  databaseTools,
  workshop;

  static OnboardingTarget? fromName(Object? value) {
    for (final target in values) {
      if (target.name == value) return target;
    }
    return null;
  }
}

enum OnboardingTooltipPlacement {
  top,
  bottom;

  static OnboardingTooltipPlacement? fromName(Object? value) {
    for (final placement in values) {
      if (placement.name == value) return placement;
    }
    return null;
  }
}

class OnboardingStep {
  const OnboardingStep({
    required this.id,
    required this.target,
    required this.title,
    required this.message,
    required this.placement,
  });

  final String id;
  final OnboardingTarget target;
  final String title;
  final String message;
  final OnboardingTooltipPlacement placement;

  factory OnboardingStep.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Ein Schritt ist ungültig.');
    final target = OnboardingTarget.fromName(raw['target']);
    final placement = OnboardingTooltipPlacement.fromName(raw['placement']);
    final id = raw['id'];
    final title = raw['title'];
    final message = raw['message'];
    if (target == null ||
        placement == null ||
        id is! String ||
        title is! String ||
        message is! String ||
        id.trim().isEmpty ||
        title.trim().isEmpty ||
        message.trim().isEmpty) {
      throw const FormatException('Ein Schritt enthält ungültige Felder.');
    }
    return OnboardingStep(
      id: id,
      target: target,
      title: title,
      message: message,
      placement: placement,
    );
  }
}

class OnboardingDefinition {
  const OnboardingDefinition({required this.name, required this.steps});

  final String name;
  final List<OnboardingStep> steps;

  factory OnboardingDefinition.fromJsonString(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map || raw['schemaVersion'] != 1 || raw['name'] is! String) {
      throw const FormatException('Keine gültige Onboarding-Datei.');
    }
    final rawSteps = raw['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw const FormatException('Das Onboarding enthält keine Schritte.');
    }
    final steps = rawSteps.map(OnboardingStep.fromJson).toList(growable: false);
    final ids = steps.map((step) => step.id).toSet();
    if (ids.length != steps.length) {
      throw const FormatException('Schritt-IDs müssen eindeutig sein.');
    }
    return OnboardingDefinition(name: raw['name'] as String, steps: steps);
  }
}

OnboardingDefinition defaultNodeQlOnboarding(TranslationCatalog catalog) {
  return OnboardingDefinition(
    name: catalog.text('onboarding.title'),
    steps: [
      OnboardingStep(
        id: 'find-nodes',
        target: OnboardingTarget.nodePalette,
        title: catalog.text('onboarding.nodes.title'),
        message: catalog.text('onboarding.nodes.message'),
        placement: OnboardingTooltipPlacement.bottom,
      ),
      OnboardingStep(
        id: 'build-query',
        target: OnboardingTarget.workspace,
        title: catalog.text('onboarding.workspace.title'),
        message: catalog.text('onboarding.workspace.message'),
        placement: OnboardingTooltipPlacement.top,
      ),
      OnboardingStep(
        id: 'use-tools',
        target: OnboardingTarget.databaseTools,
        title: catalog.text('onboarding.database.title'),
        message: catalog.text(
          kIsWeb
              ? 'onboarding.database.webMessage'
              : 'onboarding.database.message',
        ),
        placement: OnboardingTooltipPlacement.bottom,
      ),
      OnboardingStep(
        id: 'learn-in-workshop',
        target: OnboardingTarget.workshop,
        title: catalog.text('onboarding.workshop.title'),
        message: catalog.text('onboarding.workshop.message'),
        placement: OnboardingTooltipPlacement.bottom,
      ),
    ],
  );
}

/// An in-app walkthrough layer. The workbench maps Studio target IDs to its
/// real widgets and provides their rectangles through [targetRectFor].
class NodeQlOnboardingOverlay extends StatelessWidget {
  const NodeQlOnboardingOverlay({
    required this.definition,
    required this.stepIndex,
    required this.targetRectFor,
    required this.onNext,
    required this.onSkip,
    required this.catalog,
    super.key,
  });

  final OnboardingDefinition definition;
  final int stepIndex;
  final Rect? Function(OnboardingTarget target) targetRectFor;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final step = definition.steps[stepIndex];
    final targetRect = targetRectFor(step.target);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final tooltipWidth = (size.width - 32).clamp(0.0, 360.0).toDouble();
        final tooltipPosition = _tooltipPosition(
          targetRect: targetRect,
          size: size,
          width: tooltipWidth,
          placement: step.placement,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(
                  painter: _OnboardingScrimPainter(targetRect),
                ),
              ),
            ),
            Positioned(
              left: tooltipPosition.dx,
              top: tooltipPosition.dy,
              width: tooltipWidth,
              child: _OnboardingTooltip(
                step: step,
                currentStep: stepIndex + 1,
                totalSteps: definition.steps.length,
                onNext: onNext,
                onSkip: onSkip,
                catalog: catalog,
              ),
            ),
          ],
        );
      },
    );
  }

  Offset _tooltipPosition({
    required Rect? targetRect,
    required Size size,
    required double width,
    required OnboardingTooltipPlacement placement,
  }) {
    const margin = 16.0;
    const estimatedHeight = 210.0;
    if (targetRect == null) {
      return Offset(
        ((size.width - width) / 2).clamp(margin, size.width - width - margin),
        ((size.height - estimatedHeight) / 2).clamp(
          margin,
          size.height - estimatedHeight - margin,
        ),
      );
    }
    final left = (targetRect.center.dx - width / 2).clamp(
      margin,
      size.width - width - margin,
    );
    final wantedTop = placement == OnboardingTooltipPlacement.top
        ? targetRect.top - estimatedHeight - margin
        : targetRect.bottom + margin;
    return Offset(
      left,
      wantedTop.clamp(margin, size.height - estimatedHeight - margin),
    );
  }
}

class _OnboardingTooltip extends StatelessWidget {
  const _OnboardingTooltip({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
    required this.catalog,
  });

  final OnboardingStep step;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 16,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$currentStep / $totalSteps',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              step.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(step.message),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  key: const ValueKey<String>('onboarding-skip'),
                  onPressed: onSkip,
                  child: Text(catalog.text('onboarding.skip')),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey<String>('onboarding-next'),
                  onPressed: onNext,
                  child: Text(
                    catalog.text(
                      currentStep == totalSteps
                          ? 'onboarding.done'
                          : 'onboarding.next',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingScrimPainter extends CustomPainter {
  const _OnboardingScrimPainter(this.targetRect);

  final Rect? targetRect;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xB8000000));
    final target = targetRect;
    if (target != null) {
      final highlight = RRect.fromRectAndRadius(
        target.inflate(6),
        const Radius.circular(12),
      );
      canvas.drawRRect(highlight, Paint()..blendMode = BlendMode.clear);
      canvas.drawRRect(
        highlight,
        Paint()
          ..color = const Color(0xFF67E8F9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OnboardingScrimPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect;
}
