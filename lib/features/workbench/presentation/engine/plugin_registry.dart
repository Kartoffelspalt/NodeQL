import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scratchql_creater/engine/block/block_node.dart';

class PluginPaletteEntry {
  const PluginPaletteEntry({
    required this.pluginName,
    required this.blockType,
    this.labelOverride,
    this.defaults = const <String, dynamic>{},
  });

  final String pluginName;
  final BlockType blockType;
  final String? labelOverride;
  final Map<String, dynamic> defaults;
}

final pluginPaletteProvider =
    StateNotifierProvider<PluginPaletteController, List<PluginPaletteEntry>>(
      (ref) => PluginPaletteController(),
    );

class PluginPaletteController extends StateNotifier<List<PluginPaletteEntry>> {
  PluginPaletteController() : super(const <PluginPaletteEntry>[]);

  Future<void> reload() async {
    final support = await getApplicationSupportDirectory();
    final pluginsDir = Directory(p.join(support.path, 'scratchql_plugins'));
    if (!await pluginsDir.exists()) {
      state = const <PluginPaletteEntry>[];
      return;
    }

    final entries = <PluginPaletteEntry>[];
    await for (final entity in pluginsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        if (raw.trim().isEmpty) continue;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final pluginName =
            '${decoded['name'] ?? p.basenameWithoutExtension(entity.path)}';
        final blocks = (decoded['blocks'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, dynamic>>();
        for (final b in blocks) {
          final typeName = '${b['type'] ?? ''}';
          final match = BlockType.values.where((t) => t.name == typeName);
          if (match.isEmpty) continue;
          entries.add(
            PluginPaletteEntry(
              pluginName: pluginName,
              blockType: match.first,
              labelOverride: b['label'] as String?,
              defaults:
                  (b['defaults'] as Map<String, dynamic>?) ??
                  const <String, dynamic>{},
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }
    state = entries;
  }
}
