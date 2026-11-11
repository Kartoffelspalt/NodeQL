import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';

typedef WorkshopAdminActionBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
      ValueChanged<AuthoredLearningPath> onStart,
    );

/// Empty in the public app. The separate admin entry point overrides this
/// provider, which keeps all authoring UI outside the release import graph.
final workshopAdminActionProvider = Provider<WorkshopAdminActionBuilder?>(
  (_) => null,
);

typedef WorkshopAdminPanelBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
      Future<void> Function(AuthoredLearningPath) onStart,
    );

final workshopAdminPanelProvider = Provider<WorkshopAdminPanelBuilder?>(
  (_) => null,
);

final workshopAuthoringProvider = StateProvider<bool>((_) => true);
final workshopAuthoringHighlightsProvider = StateProvider<Set<String>>(
  (_) => const {},
);
