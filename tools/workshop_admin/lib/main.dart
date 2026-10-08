import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/app/nodeql_app.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/workshop_admin_extension.dart';
import 'package:nodeql_workshop_admin/workshop_admin_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        learningPathLibraryProvider.overrideWith(
          (_) => LearningPathLibraryController(),
        ),
        workshopAdminActionProvider.overrideWithValue(
          (context, ref, onStart) => WorkshopAdminLauncher(onStart: onStart),
        ),
      ],
      child: const NodeQlApp(),
    ),
  );
}
