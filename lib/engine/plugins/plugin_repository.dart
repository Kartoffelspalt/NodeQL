import 'dart:convert';

class PluginRepositorySource {
  const PluginRepositorySource({required this.url, this.enabled = true});

  final Uri url;
  final bool enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url.toString(),
    'enabled': enabled,
  };

  factory PluginRepositorySource.fromJson(Map<String, dynamic> json) {
    return PluginRepositorySource(
      url: validatePluginRepositoryUrl('${json['url'] ?? ''}'),
      enabled: json['enabled'] != false,
    );
  }
}

class PluginRepositoryEntry {
  const PluginRepositoryEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.manifestUrl,
    required this.sha256,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final Uri manifestUrl;
  final String sha256;

  factory PluginRepositoryEntry.fromJson(
    Map<String, dynamic> json, {
    required Uri repositoryUrl,
  }) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    final version = '${json['version'] ?? ''}'.trim();
    final description = '${json['description'] ?? ''}'.trim();
    final manifestUrl = repositoryUrl.resolve(
      '${json['manifestUrl'] ?? ''}'.trim(),
    );
    final sha256 = '${json['sha256'] ?? ''}'.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]+(?:\.[a-z0-9-]+)+$').hasMatch(id)) {
      throw FormatException('Invalid repository plugin ID "$id".');
    }
    if (name.isEmpty || version.isEmpty) {
      throw const FormatException(
        'Repository plugins require name and version.',
      );
    }
    validatePluginRepositoryUrl(manifestUrl.toString());
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw FormatException('Plugin "$id" has an invalid SHA-256 hash.');
    }
    return PluginRepositoryEntry(
      id: id,
      name: name,
      version: version,
      description: description,
      manifestUrl: manifestUrl,
      sha256: sha256,
    );
  }
}

class PluginRepositoryCatalog {
  const PluginRepositoryCatalog({required this.name, required this.entries});

  final String name;
  final List<PluginRepositoryEntry> entries;

  factory PluginRepositoryCatalog.fromBytes(
    List<int> bytes, {
    required Uri repositoryUrl,
  }) {
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('Plugin repository exceeds 1 MiB.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'Plugin repository must use schemaVersion 1.',
      );
    }
    final rawPlugins =
        decoded['plugins'] as List<dynamic>? ?? const <dynamic>[];
    final entries = rawPlugins
        .map(
          (value) => PluginRepositoryEntry.fromJson(
            Map<String, dynamic>.from(value as Map),
            repositoryUrl: repositoryUrl,
          ),
        )
        .toList(growable: false);
    return PluginRepositoryCatalog(
      name: '${decoded['name'] ?? repositoryUrl.host}',
      entries: entries,
    );
  }
}

Uri validatePluginRepositoryUrl(String value) {
  final uri = Uri.parse(value.trim());
  final local = const <String>{
    'localhost',
    '127.0.0.1',
    '::1',
  }.contains(uri.host);
  if (uri.host.isEmpty ||
      (uri.scheme != 'https' && !(local && uri.scheme == 'http'))) {
    throw const FormatException(
      'Plugin repositories must use HTTPS; localhost may use HTTP.',
    );
  }
  return uri;
}
