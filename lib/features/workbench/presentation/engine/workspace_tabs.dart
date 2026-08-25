import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';

class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.name,
    required this.workspaceJson,
  });

  final String id;
  final String name;
  final String workspaceJson;

  WorkspaceTab copyWith({String? name, String? workspaceJson}) => WorkspaceTab(
    id: id,
    name: name ?? this.name,
    workspaceJson: workspaceJson ?? this.workspaceJson,
  );
}

class WorkspaceTabsState {
  const WorkspaceTabsState({
    required this.tabs,
    required this.activeTabId,
    this.revision = 0,
  });

  final List<WorkspaceTab> tabs;
  final String activeTabId;
  final int revision;

  WorkspaceTab get activeTab =>
      tabs.firstWhere((tab) => tab.id == activeTabId, orElse: () => tabs.first);
}

final workspaceTabsProvider =
    StateNotifierProvider<WorkspaceTabsController, WorkspaceTabsState>((ref) {
      final workspace = ref.read(workspaceProvider.notifier);
      return WorkspaceTabsController(
        workspace,
        initialWorkspaceJson: workspace.toJsonString(),
      );
    });

class WorkspaceTabsController extends StateNotifier<WorkspaceTabsState> {
  WorkspaceTabsController(
    this._workspace, {
    required String initialWorkspaceJson,
  }) : super(
         WorkspaceTabsState(
           tabs: <WorkspaceTab>[
             WorkspaceTab(
               id: 'query_1',
               name: 'Query 1',
               workspaceJson: initialWorkspaceJson,
             ),
           ],
           activeTabId: 'query_1',
         ),
       );

  final WorkspaceController _workspace;

  void addTab({String? name}) {
    final tabs = _withCurrentWorkspace();
    final id = 'query_${DateTime.now().microsecondsSinceEpoch}';
    final workspaceJson = _emptyWorkspaceJson(id);
    final tab = WorkspaceTab(
      id: id,
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : 'Query ${tabs.length + 1}',
      workspaceJson: workspaceJson,
    );
    state = WorkspaceTabsState(
      tabs: <WorkspaceTab>[...tabs, tab],
      activeTabId: id,
      revision: state.revision + 1,
    );
    _workspace.loadFromJsonString(workspaceJson);
  }

  void selectTab(String id) {
    if (id == state.activeTabId || !state.tabs.any((tab) => tab.id == id)) {
      return;
    }
    final tabs = _withCurrentWorkspace();
    final target = tabs.firstWhere((tab) => tab.id == id);
    state = WorkspaceTabsState(
      tabs: tabs,
      activeTabId: id,
      revision: state.revision + 1,
    );
    _workspace.loadFromJsonString(target.workspaceJson);
  }

  void renameTab(String id, String name) {
    final trimmedName = name.trim();
    final index = state.tabs.indexWhere((tab) => tab.id == id);
    if (index == -1 ||
        trimmedName.isEmpty ||
        state.tabs[index].name == trimmedName) {
      return;
    }
    final tabs = _withCurrentWorkspace();
    tabs[index] = tabs[index].copyWith(name: trimmedName);
    state = WorkspaceTabsState(
      tabs: tabs,
      activeTabId: state.activeTabId,
      revision: state.revision + 1,
    );
  }

  bool deleteTab(String id) {
    if (state.tabs.length <= 1) return false;
    final index = state.tabs.indexWhere((tab) => tab.id == id);
    if (index == -1) return false;

    final deletingActiveTab = id == state.activeTabId;
    final tabs = _withCurrentWorkspace()..removeAt(index);
    var activeTabId = state.activeTabId;
    if (deletingActiveTab) {
      final fallbackIndex = index < tabs.length ? index : tabs.length - 1;
      activeTabId = tabs[fallbackIndex].id;
    }
    state = WorkspaceTabsState(
      tabs: tabs,
      activeTabId: activeTabId,
      revision: state.revision + 1,
    );
    if (deletingActiveTab) {
      _workspace.loadFromJsonString(
        tabs.firstWhere((tab) => tab.id == activeTabId).workspaceJson,
      );
    }
    return true;
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.tabs.length) return;
    final tabs = _withCurrentWorkspace();
    final targetIndex = newIndex;
    if (targetIndex < 0 || targetIndex >= tabs.length) return;
    final moved = tabs.removeAt(oldIndex);
    tabs.insert(targetIndex, moved);
    state = WorkspaceTabsState(
      tabs: tabs,
      activeTabId: state.activeTabId,
      revision: state.revision + 1,
    );
  }

  void resetToCurrentWorkspace({String name = 'Query 1'}) {
    final workspaceJson = _workspace.toJsonString();
    state = WorkspaceTabsState(
      tabs: <WorkspaceTab>[
        WorkspaceTab(id: 'query_1', name: name, workspaceJson: workspaceJson),
      ],
      activeTabId: 'query_1',
      revision: state.revision + 1,
    );
  }

  List<BlockNode> executionRoots() {
    final currentWorkspace = _workspace.toJsonString();
    return <BlockNode>[
      for (final tab in state.tabs)
        ..._rootsFromJson(
          tab.id == state.activeTabId ? currentWorkspace : tab.workspaceJson,
        ),
    ];
  }

  Map<String, dynamic> toProjectJson() {
    final currentWorkspace = _workspace.toJsonString();
    return <String, dynamic>{
      'activeTabId': state.activeTabId,
      'items': <Map<String, dynamic>>[
        for (final tab in state.tabs)
          <String, dynamic>{
            'id': tab.id,
            'name': tab.name,
            'workspace': jsonDecode(
              tab.id == state.activeTabId
                  ? currentWorkspace
                  : tab.workspaceJson,
            ),
          },
      ],
    };
  }

  bool loadFromProjectJson(Object? raw) {
    if (raw is! Map) return false;
    final items = raw['items'];
    if (items is! List) return false;
    final tabs = <WorkspaceTab>[];
    for (final item in items) {
      if (item is! Map || item['workspace'] is! Map) continue;
      final id = '${item['id'] ?? ''}'.trim();
      if (id.isEmpty || tabs.any((tab) => tab.id == id)) continue;
      tabs.add(
        WorkspaceTab(
          id: id,
          name: '${item['name'] ?? ''}'.trim().isEmpty
              ? 'Query ${tabs.length + 1}'
              : '${item['name']}'.trim(),
          workspaceJson: jsonEncode(item['workspace']),
        ),
      );
    }
    if (tabs.isEmpty) return false;
    final requestedActive = '${raw['activeTabId'] ?? ''}';
    final activeId = tabs.any((tab) => tab.id == requestedActive)
        ? requestedActive
        : tabs.first.id;
    state = WorkspaceTabsState(
      tabs: tabs,
      activeTabId: activeId,
      revision: state.revision + 1,
    );
    _workspace.loadFromJsonString(
      tabs.firstWhere((tab) => tab.id == activeId).workspaceJson,
    );
    return true;
  }

  List<WorkspaceTab> _withCurrentWorkspace() {
    final currentWorkspace = _workspace.toJsonString();
    return <WorkspaceTab>[
      for (final tab in state.tabs)
        tab.id == state.activeTabId
            ? tab.copyWith(workspaceJson: currentWorkspace)
            : tab,
    ];
  }

  List<BlockNode> _rootsFromJson(String source) {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final roots = decoded['roots'] as List<dynamic>? ?? const <dynamic>[];
    return roots
        .whereType<Map>()
        .map((root) => BlockNode.fromJson(Map<String, dynamic>.from(root)))
        .toList(growable: false);
  }

  String _emptyWorkspaceJson(String id) => jsonEncode(<String, dynamic>{
    'roots': <Map<String, dynamic>>[
      EventBlock(id: 'event_$id', position: const Offset(120, 120)).toJson(),
    ],
    'scale': 1,
    'pan': <String, double>{'dx': 0, 'dy': 0},
  });
}
