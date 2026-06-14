import 'dart:convert';

const translationSchemaVersion = 1;
const maxTranslationManifestBytes = 256 * 1024;
const maxTranslationPackageBytes = 2 * 1024 * 1024;

enum TranslationDirection { ltr, rtl }

class TranslationManifest {
  const TranslationManifest({
    required this.generatedAt,
    required this.minimumAppVersion,
    required this.languages,
  });

  final DateTime generatedAt;
  final String minimumAppVersion;
  final List<TranslationLanguage> languages;

  factory TranslationManifest.fromBytes(List<int> bytes) {
    if (bytes.length > maxTranslationManifestBytes) {
      throw const FormatException('Translation manifest exceeds 256 KiB.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Translation manifest must be an object.');
    }
    final json = Map<String, dynamic>.from(decoded);
    _requireFields(json, const {
      'schemaVersion',
      'generatedAt',
      'minimumAppVersion',
      'languages',
    }, 'translation manifest');
    if (json['schemaVersion'] != translationSchemaVersion) {
      throw FormatException(
        'Unsupported translation manifest schema: ${json['schemaVersion']}.',
      );
    }
    final generatedAt = DateTime.tryParse('${json['generatedAt']}');
    if (generatedAt == null) {
      throw const FormatException('Manifest generatedAt is invalid.');
    }
    final rawLanguages = json['languages'];
    if (rawLanguages is! List) {
      throw const FormatException('Manifest languages must be a list.');
    }
    final languages = rawLanguages
        .map(
          (value) => TranslationLanguage.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
    final locales = <String>{};
    for (final language in languages) {
      if (!locales.add(language.locale)) {
        throw FormatException(
          'Manifest contains duplicate locale "${language.locale}".',
        );
      }
    }
    return TranslationManifest(
      generatedAt: generatedAt,
      minimumAppVersion: _requiredString(json, 'minimumAppVersion'),
      languages: languages,
    );
  }
}

class TranslationLanguage {
  const TranslationLanguage({
    required this.locale,
    required this.nativeName,
    required this.direction,
    required this.revision,
    required this.completion,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
  });

  final String locale;
  final String nativeName;
  final TranslationDirection direction;
  final int revision;
  final int completion;
  final Uri downloadUrl;
  final String sha256;
  final int size;

  factory TranslationLanguage.fromJson(Map<String, dynamic> json) {
    _requireFields(json, const {
      'locale',
      'nativeName',
      'direction',
      'revision',
      'completion',
      'downloadUrl',
      'sha256',
      'size',
    }, 'translation language');
    final locale = normalizeLocaleTag(_requiredString(json, 'locale'));
    final directionName = _requiredString(json, 'direction');
    final direction = TranslationDirection.values
        .where((value) => value.name == directionName)
        .firstOrNull;
    if (direction == null) {
      throw FormatException('Unsupported text direction "$directionName".');
    }
    final revision = _requiredInt(json, 'revision');
    final completion = _requiredInt(json, 'completion');
    final size = _requiredInt(json, 'size');
    if (revision < 1 || completion < 0 || completion > 100 || size < 1) {
      throw const FormatException('Invalid translation language metadata.');
    }
    if (size > maxTranslationPackageBytes) {
      throw const FormatException('Translation package exceeds 2 MiB.');
    }
    final downloadUrl = Uri.tryParse(_requiredString(json, 'downloadUrl'));
    if (downloadUrl == null || !downloadUrl.hasAuthority) {
      throw const FormatException('Translation downloadUrl is invalid.');
    }
    final hash = _requiredString(json, 'sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Translation SHA-256 is invalid.');
    }
    return TranslationLanguage(
      locale: locale,
      nativeName: _requiredString(json, 'nativeName'),
      direction: direction,
      revision: revision,
      completion: completion,
      downloadUrl: downloadUrl,
      sha256: hash,
      size: size,
    );
  }
}

class TranslationPackage {
  const TranslationPackage({
    required this.locale,
    required this.revision,
    required this.messages,
  });

  final String locale;
  final int revision;
  final Map<String, String> messages;

  factory TranslationPackage.fromBytes(
    List<int> bytes, {
    required Set<String> knownKeys,
    required Map<String, String> englishMessages,
  }) {
    if (bytes.length > maxTranslationPackageBytes) {
      throw const FormatException('Translation package exceeds 2 MiB.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Translation package must be an object.');
    }
    final json = Map<String, dynamic>.from(decoded);
    _requireFields(json, const {
      'schemaVersion',
      'locale',
      'revision',
      'messages',
    }, 'translation package');
    if (json['schemaVersion'] != translationSchemaVersion) {
      throw FormatException(
        'Unsupported translation package schema: ${json['schemaVersion']}.',
      );
    }
    final revision = _requiredInt(json, 'revision');
    if (revision < 1) {
      throw const FormatException('Translation revision must be positive.');
    }
    final rawMessages = json['messages'];
    if (rawMessages is! Map) {
      throw const FormatException('Translation messages must be an object.');
    }
    final messages = <String, String>{};
    for (final entry in rawMessages.entries) {
      final key = '${entry.key}';
      if (!knownKeys.contains(key)) continue;
      final value = entry.value;
      if (value is! String || value.isEmpty) {
        throw FormatException('Translation "$key" must be a non-empty string.');
      }
      final expected = placeholdersIn(englishMessages[key] ?? '');
      final actual = placeholdersIn(value);
      if (!_sameSet(expected, actual)) {
        throw FormatException(
          'Translation "$key" has incompatible placeholders.',
        );
      }
      messages[key] = value;
    }
    return TranslationPackage(
      locale: normalizeLocaleTag(_requiredString(json, 'locale')),
      revision: revision,
      messages: Map.unmodifiable(messages),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': translationSchemaVersion,
    'locale': locale,
    'revision': revision,
    'messages': messages,
  };
}

String normalizeLocaleTag(String value) {
  final normalized = value.trim().replaceAll('_', '-');
  if (!RegExp(
    r'^[A-Za-z]{2,3}(?:-[A-Za-z]{2}|-[A-Za-z]{4})?$',
  ).hasMatch(normalized)) {
    throw FormatException('Invalid locale "$value".');
  }
  final parts = normalized.split('-');
  if (parts.length == 1) return parts.first.toLowerCase();
  return '${parts.first.toLowerCase()}-${parts.last.toUpperCase()}';
}

Set<String> placeholdersIn(String value) => RegExp(
  r'\{([A-Za-z_][A-Za-z0-9_]*)\}',
).allMatches(value).map((match) => match.group(1)!).toSet();

bool versionAtLeast(String current, String minimum) {
  List<int>? parse(String value) {
    final match = RegExp(r'^v?(\d+(?:\.\d+){0,3})').firstMatch(value.trim());
    return match?.group(1)?.split('.').map(int.parse).toList(growable: false);
  }

  final left = parse(current);
  final right = parse(minimum);
  if (left == null || right == null) return false;
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index += 1) {
    final a = index < left.length ? left[index] : 0;
    final b = index < right.length ? right[index] : 0;
    if (a != b) return a > b;
  }
  return true;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

void _requireFields(
  Map<String, dynamic> json,
  Set<String> allowed,
  String context,
) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException(
      '$context contains unknown field(s): ${unknown.join(', ')}.',
    );
  }
  final missing = allowed.difference(json.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException(
      '$context is missing field(s): ${missing.join(', ')}.',
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
