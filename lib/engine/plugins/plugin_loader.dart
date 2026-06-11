import 'dart:convert';
import 'dart:io';

import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
import 'package:path/path.dart' as p;

class PluginLoadIssue {
  const PluginLoadIssue({required this.path, required this.message});

  final String path;
  final String message;
}

class PluginLoadResult {
  const PluginLoadResult({
    required this.manifests,
    required this.blocks,
    required this.issues,
  });

  final List<NodeQlPluginManifest> manifests;
  final List<NodeQlPluginBlock> blocks;
  final List<PluginLoadIssue> issues;

  Map<String, NodeQlPluginBlock> get blocksByQualifiedId =>
      <String, NodeQlPluginBlock>{
        for (final block in blocks) block.qualifiedId: block,
      };
}

class NodeQlPluginLoader {
  const NodeQlPluginLoader({required this.currentNodeQlVersion});

  static const int maxManifestBytes = 1024 * 1024;

  final String currentNodeQlVersion;

  Future<PluginLoadResult> load(Directory root) async {
    if (!await root.exists()) {
      return const PluginLoadResult(
        manifests: <NodeQlPluginManifest>[],
        blocks: <NodeQlPluginBlock>[],
        issues: <PluginLoadIssue>[],
      );
    }

    final manifests = <NodeQlPluginManifest>[];
    final blocks = <NodeQlPluginBlock>[];
    final issues = <PluginLoadIssue>[];
    final candidates = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        final manifest = File(p.join(entity.path, 'plugin.json'));
        if (await manifest.exists()) candidates.add(manifest);
      } else if (entity is File && entity.path.endsWith('.json')) {
        candidates.add(entity);
      }
    }
    candidates.sort((a, b) => a.path.compareTo(b.path));

    final pluginIds = <String>{};
    final blockIds = <String>{};
    for (final candidate in candidates) {
      try {
        if (await candidate.length() > maxManifestBytes) {
          throw const FormatException('Plugin manifest exceeds 1 MiB.');
        }
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is! Map) {
          throw const FormatException('Plugin manifest must be a JSON object.');
        }
        final json = Map<String, dynamic>.from(decoded);
        if (json.containsKey('schemaVersion')) {
          final manifest = NodeQlPluginManifest.fromJson(json);
          if (!isCompatible(manifest.minNodeQlVersion)) {
            throw FormatException(
              'Plugin requires NodeQL ${manifest.minNodeQlVersion} or newer; '
              'this app is $currentNodeQlVersion.',
            );
          }
          if (pluginIds.contains(manifest.id)) {
            throw FormatException('Duplicate plugin ID "${manifest.id}".');
          }
          final manifestBlockIds = manifest.blocks
              .map((block) => block.qualifiedId)
              .toSet();
          final duplicates = manifestBlockIds.intersection(blockIds);
          if (duplicates.isNotEmpty) {
            throw FormatException(
              'Duplicate plugin block ID "${duplicates.first}".',
            );
          }
          pluginIds.add(manifest.id);
          blockIds.addAll(manifestBlockIds);
          manifests.add(manifest);
          blocks.addAll(manifest.blocks);
        } else {
          final legacyBlocks = _readLegacy(candidate, json);
          for (final block in legacyBlocks) {
            if (!blockIds.add(block.qualifiedId)) {
              throw FormatException(
                'Duplicate plugin block ID "${block.qualifiedId}".',
              );
            }
          }
          blocks.addAll(legacyBlocks);
        }
      } on Object catch (error) {
        issues.add(PluginLoadIssue(path: candidate.path, message: '$error'));
      }
    }

    return PluginLoadResult(
      manifests: manifests,
      blocks: blocks,
      issues: issues,
    );
  }

  List<NodeQlPluginBlock> _readLegacy(File source, Map<String, dynamic> json) {
    final pluginName =
        '${json['name'] ?? p.basenameWithoutExtension(source.path)}';
    final safeId = p
        .basenameWithoutExtension(source.path)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final pluginId = 'legacy.${safeId.isEmpty ? 'plugin' : safeId}';
    final rawBlocks = json['blocks'] as List<dynamic>? ?? const <dynamic>[];
    final result = <NodeQlPluginBlock>[];
    for (var index = 0; index < rawBlocks.length; index++) {
      final value = rawBlocks[index];
      if (value is! Map) continue;
      final blockJson = Map<String, dynamic>.from(value);
      final typeName = '${blockJson['type'] ?? ''}';
      final matches = BlockType.values.where(
        (candidate) => candidate.name == typeName,
      );
      if (matches.isEmpty) continue;
      result.add(
        NodeQlPluginBlock.legacy(
          pluginId: pluginId,
          pluginName: pluginName,
          pluginVersion: '0.0.0',
          index: index,
          nativeBlockType: matches.first,
          label: blockJson['label'] as String?,
          defaults: Map<String, dynamic>.from(
            blockJson['defaults'] as Map? ?? const <String, dynamic>{},
          ),
        ),
      );
    }
    return result;
  }

  bool isCompatible(String? minimum) {
    if (minimum == null) return true;
    final current = _versionParts(currentNodeQlVersion);
    final required = _versionParts(minimum);
    for (var index = 0; index < 3; index++) {
      if (current[index] > required[index]) return true;
      if (current[index] < required[index]) return false;
    }
    return true;
  }

  List<int> _versionParts(String version) {
    final stable = version.split(RegExp(r'[+-]')).first;
    return stable.split('.').take(3).map(int.parse).toList(growable: false);
  }
}
