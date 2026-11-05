import 'dart:io';

import 'package:http/http.dart' as http;

import 'src/ai_translation_generator.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln('''Generate NodeQL release language packages with Gemini.
Run from the repository root. Options use --name=value.
  --locales=de,fr,...       Defaults to NODEQL_TRANSLATION_LOCALES or $defaultTranslationLocales
  --revision=NUMBER        Release build number (required)
  --model=MODEL            Or NODEQL_TRANSLATION_MODEL; default: $defaultGeminiTranslationModel
  --source=FILE            Default: assets/translations/en.json
  --reviewed-dir=DIR       Default: translations
  --output=DIR             Default: build/ai-translations/packages
  --state=FILE             Default: build/ai-translations/state.json
  --batch-size=NUMBER      Default: 40 (maximum 100)
  --concurrency=NUMBER     Parallel batches; default: 3 (maximum 8)
  --dry-run                Report work without API calls or file changes
Credentials: GEMINI_API_KEY environment variable only.
See docs/localization/README.md for GitHub Actions configuration.''');
    return;
  }
  final httpClient = http.Client();
  try {
    final options = <String, String>{};
    const allowed = {
      'locales',
      'revision',
      'model',
      'source',
      'reviewed-dir',
      'output',
      'state',
      'batch-size',
      'concurrency',
    };
    for (final argument in arguments) {
      if (argument == '--dry-run') continue;
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') ||
          separator < 3 ||
          !allowed.contains(argument.substring(2, separator))) {
        throw const FormatException('Unknown option. Use --help for usage.');
      }
      options[argument.substring(2, separator)] = argument.substring(
        separator + 1,
      );
    }
    final env = Platform.environment;
    String? configured(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final locales =
        (configured(options['locales']) ??
                configured(env['NODEQL_TRANSLATION_LOCALES']) ??
                defaultTranslationLocales)
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
    if (locales.isEmpty) {
      throw const FormatException('At least one target locale is required.');
    }
    final revision = int.tryParse(options['revision'] ?? '');
    final batchSize = int.tryParse(options['batch-size'] ?? '40');
    final concurrency = int.tryParse(
      options['concurrency'] ??
          configured(env['NODEQL_TRANSLATION_CONCURRENCY']) ??
          '3',
    );
    if (revision == null || batchSize == null || concurrency == null) {
      throw const FormatException(
        'A numeric --revision is required; --batch-size and --concurrency must be numeric.',
      );
    }
    GeminiTranslationClient? translator;
    await generateTranslationPackages(
      locales: locales,
      revision: revision,
      source: File(options['source'] ?? 'assets/translations/en.json'),
      reviewed: Directory(options['reviewed-dir'] ?? 'translations'),
      output: Directory(options['output'] ?? 'build/ai-translations/packages'),
      stateFile: File(options['state'] ?? 'build/ai-translations/state.json'),
      batchSize: batchSize,
      concurrency: concurrency,
      dryRun: arguments.contains('--dry-run'),
      log: stdout.writeln,
      translate: (locale, messages) {
        translator ??= GeminiTranslationClient(
          client: httpClient,
          model:
              configured(options['model']) ??
              configured(env['NODEQL_TRANSLATION_MODEL']) ??
              defaultGeminiTranslationModel,
          apiKey: env['GEMINI_API_KEY'] ?? '',
        );
        return translator!.translate(locale, messages);
      },
    );
  } on Object catch (error) {
    // FormatException.toString can include provider content. Never echo it.
    stderr.writeln(
      error is FormatException
          ? error.message
          : error is FileSystemException
          ? 'Could not read/write translation files: ${error.path}'
          : error is TranslationRequestException
          ? '$error'
          : 'Translation generation failed (${error.runtimeType}).',
    );
    exitCode = 1;
  } finally {
    httpClient.close();
  }
}
