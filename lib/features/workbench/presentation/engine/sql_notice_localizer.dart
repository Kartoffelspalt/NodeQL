import 'package:nodeql/localization/translation_catalog.dart';

String localizedSimpleCompileWarning(
  TranslationCatalog catalog,
  String warning,
) {
  if (warning.contains('not executable')) {
    return catalog.text('notice.compile.notExecutable');
  }
  if (warning.contains('Cycle detected')) {
    return catalog.text('notice.compile.cycle');
  }
  if (warning.contains('Plugin block')) {
    return catalog.text('notice.compile.pluginUnavailable');
  }
  if (warning.contains('failed:')) {
    return catalog.text('notice.compile.pluginFailed');
  }
  if (warning.contains('created with version')) {
    return catalog.text('notice.compile.pluginVersion');
  }
  return catalog.text('notice.compile.fallback');
}

String localizedSimpleRuntimeError(TranslationCatalog catalog, String message) {
  final normalized = message.toLowerCase();
  if (RegExp(
    r'no such table: ([^\s,)]+)',
    caseSensitive: false,
  ).hasMatch(message)) {
    return catalog.text('notice.runtime.noSuchTable');
  }
  if (RegExp(
    r'no such column: ([^\s,)]+)',
    caseSensitive: false,
  ).hasMatch(message)) {
    return catalog.text('notice.runtime.noSuchColumn');
  }
  if (normalized.contains('ambiguous column')) {
    return catalog.text('notice.runtime.ambiguousColumn');
  }
  if (normalized.contains('no such index') ||
      normalized.contains('no such view') ||
      normalized.contains('no such trigger')) {
    return catalog.text('notice.runtime.missingObject');
  }
  if (normalized.contains('already exists')) {
    return catalog.text('notice.runtime.alreadyExists');
  }
  if (normalized.contains('misuse of aggregate')) {
    return catalog.text('notice.runtime.aggregateMisuse');
  }
  if (normalized.contains('incomplete input')) {
    return catalog.text('notice.runtime.incomplete');
  }
  if (normalized.contains('syntax error') || normalized.contains('near "')) {
    return catalog.text('notice.runtime.syntax');
  }
  if (normalized.contains('unique constraint')) {
    return catalog.text('notice.runtime.unique');
  }
  if (normalized.contains('foreign key constraint')) {
    return catalog.text('notice.runtime.foreignKey');
  }
  if (normalized.contains('not null constraint')) {
    return catalog.text('notice.runtime.notNull');
  }
  if (normalized.contains('constraint')) {
    return catalog.text('notice.runtime.constraint');
  }
  if (normalized.contains('datatype mismatch')) {
    return catalog.text('notice.runtime.datatype');
  }
  if (normalized.contains('readonly') || normalized.contains('read-only')) {
    return catalog.text('notice.runtime.readonly');
  }
  if (normalized.contains('database is locked')) {
    return catalog.text('notice.runtime.locked');
  }
  if (normalized.contains('no database connected')) {
    return catalog.text('notice.runtime.noDatabase');
  }
  if (normalized.contains('database file not found')) {
    return catalog.text('notice.runtime.fileMissing');
  }
  if (normalized.contains('failed to open database')) {
    return catalog.text('notice.runtime.openFailed');
  }
  return catalog.text('notice.runtime.fallback');
}
