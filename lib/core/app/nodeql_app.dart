import 'package:flutter/material.dart';
import 'package:nodeql/localization/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/localization/locale_controller.dart';
import 'package:nodeql/ui/shell/workbench_shell.dart';

class NodeQlApp extends ConsumerWidget {
  const NodeQlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final theme = ref.watch(nodeQlThemeProvider);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      localeResolutionCallback: resolveLocale,
      theme: themeFor(theme),
      debugShowCheckedModeBanner: false,
      home: const WorkbenchShell(),
    );
  }
}
