import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'translation_models.dart';

const defaultTranslationManifestUrl = String.fromEnvironment(
  'NODEQL_TRANSLATION_MANIFEST_URL',
  defaultValue: '',
);

abstract class TranslationRepository {
  Future<Map<String, String>> loadEnglishMessages();
  Future<List<TranslationPackage>> loadCachedPackages();
  Future<TranslationManifest> fetchManifest();
  Future<TranslationPackage> install(TranslationLanguage language);
  Future<void> remove(String locale);
}

class FileTranslationRepository implements TranslationRepository {
  FileTranslationRepository({
    http.Client? client,
    Uri? manifestUri,
    Set<String> allowedHosts = const {
      'kartoffelspalt.github.io',
      'raw.githubusercontent.com',
    },
    Future<Directory> Function()? supportDirectory,
    Future<String> Function(String key)? assetLoader,
  }) : _client = client ?? http.Client(),
       _manifestUri =
           manifestUri ??
           (defaultTranslationManifestUrl.isEmpty
               ? null
               : Uri.parse(defaultTranslationManifestUrl)),
       _allowedHosts = allowedHosts,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _assetLoader = assetLoader ?? rootBundle.loadString;

  final http.Client _client;
  final Uri? _manifestUri;
  final Set<String> _allowedHosts;
  final Future<Directory> Function() _supportDirectory;
  final Future<String> Function(String key) _assetLoader;

  Map<String, String>? _englishMessages;

  @override
  Future<Map<String, String>> loadEnglishMessages() async {
    final cached = _englishMessages;
    if (cached != null) return cached;
    final raw = await _assetLoader('assets/translations/en.json');
    final rawMessages = _rawMessages(raw);
    final package = TranslationPackage.fromBytes(
      utf8.encode(raw),
      knownKeys: rawMessages.keys.toSet(),
      englishMessages: rawMessages,
    );
    _englishMessages = package.messages;
    return package.messages;
  }

  @override
  Future<List<TranslationPackage>> loadCachedPackages() async {
    final directory = await _packagesDirectory();
    if (!await directory.exists()) return const [];
    final english = await loadEnglishMessages();
    final packages = <TranslationPackage>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        packages.add(
          TranslationPackage.fromBytes(
            await entity.readAsBytes(),
            knownKeys: english.keys.toSet(),
            englishMessages: english,
          ),
        );
      } catch (_) {
        // A broken package is ignored without affecting other cached locales.
      }
    }
    return packages;
  }

  @override
  Future<TranslationManifest> fetchManifest() async {
    final uri = _manifestUri;
    if (uri == null) {
      throw StateError('NODEQL_TRANSLATION_MANIFEST_URL is not configured.');
    }
    _validateUri(uri);
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'NodeQL-Translation-Client',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Translation manifest request failed (${response.statusCode}).',
        uri: uri,
      );
    }
    return TranslationManifest.fromBytes(response.bodyBytes);
  }

  @override
  Future<TranslationPackage> install(TranslationLanguage language) async {
    _validateUri(language.downloadUrl);
    final english = await loadEnglishMessages();
    final response = await _client.get(
      language.downloadUrl,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'NodeQL-Translation-Client',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Translation download failed (${response.statusCode}).',
        uri: language.downloadUrl,
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.length != language.size) {
      throw const FormatException('Translation package size does not match.');
    }
    if (sha256.convert(bytes).toString() != language.sha256) {
      throw const FormatException('Translation package hash does not match.');
    }
    final package = TranslationPackage.fromBytes(
      bytes,
      knownKeys: english.keys.toSet(),
      englishMessages: english,
    );
    if (package.locale != language.locale ||
        package.revision != language.revision) {
      throw const FormatException(
        'Translation package metadata does not match the manifest.',
      );
    }

    final installed = await _loadCachedPackage(package.locale);
    if (installed != null && installed.revision > package.revision) {
      throw const FormatException('Translation package downgrade refused.');
    }

    final directory = await _packagesDirectory();
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, '${package.locale}.json'));
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return package;
  }

  @override
  Future<void> remove(String locale) async {
    final directory = await _packagesDirectory();
    final file = File(
      p.join(directory.path, '${normalizeLocaleTag(locale)}.json'),
    );
    if (await file.exists()) await file.delete();
  }

  Future<TranslationPackage?> _loadCachedPackage(String locale) async {
    final directory = await _packagesDirectory();
    final file = File(p.join(directory.path, '$locale.json'));
    if (!await file.exists()) return null;
    final english = await loadEnglishMessages();
    return TranslationPackage.fromBytes(
      await file.readAsBytes(),
      knownKeys: english.keys.toSet(),
      englishMessages: english,
    );
  }

  Future<Directory> _packagesDirectory() async {
    final support = await _supportDirectory();
    return Directory(p.join(support.path, 'nodeql_translations'));
  }

  void _validateUri(Uri uri) {
    if (uri.scheme != 'https' || !_allowedHosts.contains(uri.host)) {
      throw FormatException(
        'Translation URL must use HTTPS on an allowed GitHub host.',
      );
    }
  }

  Map<String, String> _rawMessages(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final messages = decoded['messages'] as Map<String, dynamic>;
    return messages.map((key, value) => MapEntry(key, '$value'));
  }
}
