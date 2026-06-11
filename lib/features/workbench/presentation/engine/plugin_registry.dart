import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/plugins/plugin_loader.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
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
  });

  final List<PluginPaletteEntry> entries;
  final List<NodeQlPluginManifest> manifests;
  final List<PluginLoadIssue> issues;
  final String? pluginsDirectory;
  final bool loading;

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
  PluginPaletteController() : super(const PluginPaletteState());

  Future<void> reload() async {
    state = PluginPaletteState(
      entries: state.entries,
      manifests: state.manifests,
      issues: state.issues,
      pluginsDirectory: state.pluginsDirectory,
      loading: true,
    );
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
    );
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
}

NodeQlPluginBlock? pluginBlockForNode(
  BlockNode node,
  PluginPaletteState plugins,
) {
  final qualifiedId = node.inputs[pluginBlockKeyInput] as String?;
  if (qualifiedId == null) return null;
  return plugins.blocksByQualifiedId[qualifiedId];
}
