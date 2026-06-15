import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/plugins/plugin_loader.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
import 'package:nodeql/engine/plugins/plugin_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PluginPaletteEntry {
  const PluginPaletteEntry(this.block);

  final NodeQlPluginBlock block;

  String get pluginName => block.pluginName;
  BlockType get blockType => block.hostBlockType;
  Map<String, dynamic> get defaults => block.workspaceDefaults;

  String labelFor(String languageCode) => block.labelFor(languageCode);
  String descriptionFor(String languageCode) =>
      block.descriptionFor(languageCode);
}

class PluginPaletteState {
  const PluginPaletteState({
    this.entries = const <PluginPaletteEntry>[],
    this.manifests = const <NodeQlPluginManifest>[],
    this.issues = const <PluginLoadIssue>[],
    this.pluginsDirectory,
    this.loading = false,
    this.repositories = const <PluginRepositorySource>[],
    this.repositoryCatalogs = const <Uri, PluginRepositoryCatalog>{},
    this.repositoryErrors = const <Uri, String>{},
  });

  final List<PluginPaletteEntry> entries;
  final List<NodeQlPluginManifest> manifests;
  final List<PluginLoadIssue> issues;
  final String? pluginsDirectory;
  final bool loading;
  final List<PluginRepositorySource> repositories;
  final Map<Uri, PluginRepositoryCatalog> repositoryCatalogs;
  final Map<Uri, String> repositoryErrors;

  Map<String, NodeQlPluginBlock> get blocksByQualifiedId =>
      <String, NodeQlPluginBlock>{
        for (final entry in entries) entry.block.qualifiedId: entry.block,
      };
}

final pluginPaletteProvider =
    StateNotifierProvider<PluginPaletteController, PluginPaletteState>(
      (ref) => PluginPaletteController(),
    );

class PluginPaletteController extends StateNotifier<PluginPaletteState> {
  PluginPaletteController({
    http.Client? httpClient,
    Future<File> Function()? repositoriesFile,
  }) : _httpClient = httpClient ?? http.Client(),
       _repositoriesFile = repositoriesFile ?? _defaultRepositoriesFile,
       super(const PluginPaletteState());

  final http.Client _httpClient;
  final Future<File> Function() _repositoriesFile;

  Future<void> reload() async {
    state = PluginPaletteState(
      entries: state.entries,
      manifests: state.manifests,
      issues: state.issues,
      pluginsDirectory: state.pluginsDirectory,
      loading: true,
      repositories: state.repositories,
      repositoryCatalogs: state.repositoryCatalogs,
      repositoryErrors: state.repositoryErrors,
    );
    final repositories = state.repositories.isEmpty
        ? await _loadRepositories()
        : state.repositories;
    final pluginsDir = await _pluginsDirectory();
    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
    }
    final package = await PackageInfo.fromPlatform();
    final result = await NodeQlPluginLoader(
      currentNodeQlVersion: package.version,
    ).load(pluginsDir);
    state = PluginPaletteState(
      entries: result.blocks
          .map(PluginPaletteEntry.new)
          .toList(growable: false),
      manifests: result.manifests,
      issues: result.issues,
      pluginsDirectory: pluginsDir.path,
      repositories: repositories,
      repositoryCatalogs: state.repositoryCatalogs,
      repositoryErrors: state.repositoryErrors,
    );
  }

  Future<void> addRepository(String url) async {
    final uri = validatePluginRepositoryUrl(url);
    if (state.repositories.any((source) => source.url == uri)) return;
    final repositories = <PluginRepositorySource>[
      ...state.repositories,
      PluginRepositorySource(url: uri),
    ];
    await _persistRepositories(repositories);
    state = PluginPaletteState(
      entries: state.entries,
      manifests: state.manifests,
      issues: state.issues,
      pluginsDirectory: state.pluginsDirectory,
      repositories: repositories,
      repositoryCatalogs: state.repositoryCatalogs,
      repositoryErrors: state.repositoryErrors,
    );
    await refreshRepositories();
  }

  Future<void> removeRepository(Uri url) async {
    final repositories = state.repositories
        .where((source) => source.url != url)
        .toList(growable: false);
    final catalogs = <Uri, PluginRepositoryCatalog>{...state.repositoryCatalogs}
      ..remove(url);
    final errors = <Uri, String>{...state.repositoryErrors}..remove(url);
    await _persistRepositories(repositories);
    state = PluginPaletteState(
      entries: state.entries,
      manifests: state.manifests,
      issues: state.issues,
      pluginsDirectory: state.pluginsDirectory,
      repositories: repositories,
      repositoryCatalogs: catalogs,
      repositoryErrors: errors,
    );
  }

  Future<void> refreshRepositories() async {
    final catalogs = <Uri, PluginRepositoryCatalog>{};
    final errors = <Uri, String>{};
    for (final source in state.repositories.where((source) => source.enabled)) {
      try {
        final response = await _httpClient
            .get(source.url)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('HTTP ${response.statusCode}');
        }
        catalogs[source.url] = PluginRepositoryCatalog.fromBytes(
          response.bodyBytes,
          repositoryUrl: source.url,
        );
      } on Object catch (error) {
        errors[source.url] = '$error';
      }
    }
    state = PluginPaletteState(
      entries: state.entries,
      manifests: state.manifests,
      issues: state.issues,
      pluginsDirectory: state.pluginsDirectory,
      repositories: state.repositories,
      repositoryCatalogs: catalogs,
      repositoryErrors: errors,
    );
  }

  Future<NodeQlPluginManifest> installRepositoryPlugin(
    PluginRepositoryEntry entry,
  ) async {
    final response = await _httpClient
        .get(entry.manifestUrl)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Plugin download failed: HTTP ${response.statusCode}.');
    }
    if (response.bodyBytes.length > NodeQlPluginLoader.maxManifestBytes) {
      throw const FormatException('Plugin manifest exceeds 1 MiB.');
    }
    final actualHash = sha256.convert(response.bodyBytes).toString();
    if (actualHash != entry.sha256) {
      throw const FormatException('Plugin manifest SHA-256 mismatch.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Plugin manifest must be a JSON object.');
    }
    final downloadedManifest = NodeQlPluginManifest.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (downloadedManifest.id != entry.id ||
        downloadedManifest.version != entry.version) {
      throw const FormatException(
        'Repository metadata does not match the plugin manifest.',
      );
    }
    final temp = await Directory.systemTemp.createTemp('nodeql-plugin-');
    try {
      final file = File(p.join(temp.path, 'plugin.json'));
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return await installManifest(file);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<NodeQlPluginManifest> installManifest(File source) async {
    if (!await source.exists()) {
      throw StateError('Plugin manifest does not exist: ${source.path}');
    }
    if (await source.length() > NodeQlPluginLoader.maxManifestBytes) {
      throw const FormatException('Plugin manifest exceeds 1 MiB.');
    }
    final decoded = jsonDecode(await source.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Plugin manifest must be a JSON object.');
    }
    final manifest = NodeQlPluginManifest.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    final package = await PackageInfo.fromPlatform();
    final loader = NodeQlPluginLoader(currentNodeQlVersion: package.version);
    if (!loader.isCompatible(manifest.minNodeQlVersion)) {
      throw FormatException(
        'Plugin requires NodeQL ${manifest.minNodeQlVersion} or newer; '
        'this app is ${package.version}.',
      );
    }

    final pluginsDir = await _pluginsDirectory();
    await pluginsDir.create(recursive: true);
    final destination = Directory(p.join(pluginsDir.path, manifest.id));
    await destination.create(recursive: true);
    final destinationPath = p.join(destination.path, 'plugin.json');
    if (!p.equals(p.absolute(source.path), p.absolute(destinationPath))) {
      await source.copy(destinationPath);
    }
    await reload();
    return manifest;
  }

  Future<void> uninstall(String pluginId) async {
    final pluginsDir = await _pluginsDirectory();
    final destination = Directory(p.join(pluginsDir.path, pluginId));
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
    await reload();
  }

  Future<Directory> _pluginsDirectory() async {
    final override = Platform.environment['NODEQL_PLUGIN_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override.trim());
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'nodeql_plugins'));
  }

  Future<List<PluginRepositorySource>> _loadRepositories() async {
    try {
      final file = await _repositoriesFile();
      if (!await file.exists()) return const <PluginRepositorySource>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const <PluginRepositorySource>[];
      return (decoded['repositories'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (value) => PluginRepositorySource.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <PluginRepositorySource>[];
    }
  }

  Future<void> _persistRepositories(
    List<PluginRepositorySource> repositories,
  ) async {
    final file = await _repositoriesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'repositories': repositories.map((source) => source.toJson()).toList(),
      }),
      flush: true,
    );
  }

  static Future<File> _defaultRepositoriesFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'nodeql_plugin_repositories.json'));
  }
}

NodeQlPluginBlock? pluginBlockForNode(
  BlockNode node,
  PluginPaletteState plugins,
) {
  final qualifiedId = node.inputs[pluginBlockKeyInput] as String?;
  if (qualifiedId == null) return null;
  return plugins.blocksByQualifiedId[qualifiedId];
}
