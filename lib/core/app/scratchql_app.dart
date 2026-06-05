import 'package:flutter/material.dart';
import 'package:scratchql_creater/localization/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scratchql_creater/core/theme/theme_controller.dart';
import 'package:scratchql_creater/localization/locale_controller.dart';
import 'package:scratchql_creater/ui/shell/workbench_shell.dart';

class ScratchQlApp extends ConsumerWidget {
  const ScratchQlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final theme = ref.watch(scratchQlThemeProvider);

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
