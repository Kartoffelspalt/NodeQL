import 'package:flutter/material.dart';
import 'package:nodeql/localization/generated/app_localizations.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:url_launcher/link.dart';

/// Explains where a feature is available before offering the desktop app link.
class DesktopFeatureNotice extends StatelessWidget {
  const DesktopFeatureNotice({
    required this.featureName,
    required this.catalog,
    super.key,
  });

  final String featureName;
  final TranslationCatalog catalog;

  static final _repositoryUri = Uri.https(
    'github.com',
    '/Kartoffelspalt/NodeQL',
  );

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    // Downloaded language packs can add locales beyond the bundled ARB files.
    final locale = AppLocalizations.supportedLocales.firstWhere(
      (locale) => locale.languageCode == languageCode,
      orElse: () => const Locale('en'),
    );
    final strings = lookupAppLocalizations(locale);
    return AlertDialog(
      key: const ValueKey('desktop-feature-notice'),
      icon: const Icon(Icons.desktop_windows_outlined),
      title: Text(featureName),
      content: Text(strings.desktopFeatureOnly),
      actions: [
        TextButton(
          key: const ValueKey('desktop-feature-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(catalog.text('common.close')),
        ),
        Link(
          uri: _repositoryUri,
          target: LinkTarget.blank,
          builder: (context, followLink) => FilledButton.icon(
            key: const ValueKey('desktop-feature-github'),
            onPressed: followLink,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('GitHub'),
          ),
        ),
      ],
    );
  }
}
