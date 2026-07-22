import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/localization/supported_languages.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:nodeql/ui/shell/workbench_shell.dart';

class NodeQlApp extends ConsumerWidget {
  const NodeQlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationControllerProvider);
    final theme = ref.watch(nodeQlThemeProvider);

    return MaterialApp(
      title: translations.catalog.text('app.name'),
      locale: translations.locale,
      supportedLocales: <Locale>{
        ...supportedLanguages.map(toLocale),
        ...translations.installed.keys.map((tag) {
          final parts = tag.split('-');
          return parts.length == 1
              ? Locale(parts.first)
              : Locale(parts.first, parts.last);
        }),
      }.toList(growable: false),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: themeFor(theme.theme, accentColor: theme.accentColor),
      debugShowCheckedModeBanner: false,
      home: const WorkbenchShell(),
    );
  }
}
