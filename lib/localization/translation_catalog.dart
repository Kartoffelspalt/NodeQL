import 'package:flutter/widgets.dart';

import 'translation_models.dart';

class TranslationCatalog {
  const TranslationCatalog({
    required this.locale,
    required this.messages,
    required this.englishMessages,
    this.direction = TranslationDirection.ltr,
  });

  final String locale;
  final Map<String, String> messages;
  final Map<String, String> englishMessages;
  final TranslationDirection direction;

  String text(String key, [Map<String, Object?> values = const {}]) {
    var result = messages[key] ?? englishMessages[key] ?? key;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }

  TextDirection get textDirection => direction == TranslationDirection.rtl
      ? TextDirection.rtl
      : TextDirection.ltr;
}
