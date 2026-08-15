import 'package:flutter_test/flutter_test.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_tabs.dart';

void main() {
  test('tabs preserve independent workspaces and execute in visible order', () {
    final workspace = WorkspaceController()..resetWithRoot();
    final tabs = WorkspaceTabsController(
      workspace,
      initialWorkspaceJson: workspace.toJsonString(),
    );

    _addSelect(workspace, 'first_table');
    final firstTabId = tabs.state.activeTabId;
    tabs.addTab(name: 'Second query');
    _addSelect(workspace, 'second_table');

    expect(
      const SqlCompiler().compileWorkspace(tabs.executionRoots()).sql,
      'SELECT * FROM first_table;\nSELECT * FROM second_table;',
    );

    tabs.reorderTabs(0, 1);
    expect(
      const SqlCompiler().compileWorkspace(tabs.executionRoots()).sql,
      'SELECT * FROM second_table;\nSELECT * FROM first_table;',
    );

    tabs.selectTab(firstTabId);
    expect(
      workspace.allBlocks().any(
        (node) =>
            node.type == BlockType.sqlSelect &&
            node.inputs['table'] == 'first_table',
      ),
      isTrue,
    );
  });

  test('tab project payload restores order and active workspace', () {
    final workspace = WorkspaceController()..resetWithRoot();
    final tabs = WorkspaceTabsController(
      workspace,
      initialWorkspaceJson: workspace.toJsonString(),
    );
    _addSelect(workspace, 'one');
    tabs.renameTab(tabs.state.activeTabId, '  Revenue report  ');
    tabs.renameTab(tabs.state.activeTabId, '   ');
    tabs.addTab(name: 'Two');
    _addSelect(workspace, 'two');
    final payload = tabs.toProjectJson();

    final restoredWorkspace = WorkspaceController()..resetWithRoot();
    final restored = WorkspaceTabsController(
      restoredWorkspace,
      initialWorkspaceJson: restoredWorkspace.toJsonString(),
    );

    expect(restored.loadFromProjectJson(payload), isTrue);
    expect(restored.state.tabs.map((tab) => tab.name), <String>[
      'Revenue report',
      'Two',
    ]);
    expect(restored.state.activeTab.name, 'Two');
    expect(
      const SqlCompiler().compileWorkspace(restored.executionRoots()).sql,
      'SELECT * FROM one;\nSELECT * FROM two;',
    );
  });
}

void _addSelect(WorkspaceController workspace, String table) {
  workspace.addTemplate(
    BlockType.sqlSelect,
    workspace.suggestedTemplatePosition(BlockType.sqlSelect),
    defaults: <String, dynamic>{'columns': '*', 'table': table},
  );
}
