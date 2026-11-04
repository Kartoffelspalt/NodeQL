import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/nodeql_app.dart';
import 'core/platform/sqlite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSqlite();
  runApp(const ProviderScope(child: NodeQlApp()));
}
