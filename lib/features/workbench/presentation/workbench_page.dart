import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/plugin_registry.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/features/workbench/presentation/scratch_style.dart';
import 'package:nodeql/features/workbench/presentation/widgets/block_shape_painter.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nodeql/localization/generated/app_localizations.dart';
import 'package:nodeql/localization/locale_controller.dart';
import 'package:nodeql/localization/supported_languages.dart';
import 'dart:io';

const int _maxVisibleColumnSelections = 3;

class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  static const _menuChannel = MethodChannel('nodeql/menu');
  final TransformationController _transform = TransformationController();
  final FocusNode _workspaceFocus = FocusNode();
  final SqlCompiler _compiler = const SqlCompiler();
  SqlPaletteCategory _activeCategory = SqlPaletteCategory.dql;
  String? _activeProjectPath;
  String _activeProjectId = 'default';
  String _activeProjectName = 'Untitled';
  List<Map<String, dynamic>> _recentProjects = <Map<String, dynamic>>[];
  int _lastAutosaveRevision = -1;
  Timer? _autosaveDebounce;
  double _paletteWidth = 250;

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleNativeMenuAction);
    Future<void>.microtask(
      () => ref.read(pluginPaletteProvider.notifier).reload(),
    );
    _restoreAutosave();
  }

  @override
  void dispose() {
    _menuChannel.setMethodCallHandler(null);
    _autosaveDebounce?.cancel();
    _workspaceFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = ref.watch(localeControllerProvider);
    final workspaceRevision = ref.watch(
      workspaceProvider.select((s) => s.revision),
    );
    final workspaceRoots = ref.read(workspaceProvider).roots;
    final runtime = ref.watch(sqlRuntimeProvider);
    final mode = ref.watch(sqlModeProvider);
    final pluginEntries = ref.watch(pluginPaletteProvider);
    final compileResult = _compiler.compileWorkspace(workspaceRoots);
    final sql = compileResult.sql;
    _maybeAutosave(workspaceRevision);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              l10n: l10n,
              localeCode: locale.languageCode,
              onLocale: (code) => ref
                  .read(localeControllerProvider.notifier)
                  .setLanguageCode(code),
              onPickDb: () =>
                  ref.read(sqlRuntimeProvider.notifier).pickDatabase(),
              onExecuteGuarded: () {
                if (compileResult.sql.trim().isEmpty) {
                  ref
                      .read(sqlRuntimeProvider.notifier)
                      .setMessage(
                        compileResult.warnings.isEmpty
                            ? 'No executable SQL chain found under EXECUTE QUERY.'
                            : compileResult.warnings.join('\n'),
                      );
                  return;
                }
                ref.read(sqlRuntimeProvider.notifier).executeWithSnapshot(sql);
                if (compileResult.warnings.isNotEmpty) {
                  ref
                      .read(sqlRuntimeProvider.notifier)
                      .setMessage(
                        'Executed with warnings:\n${compileResult.warnings.join('\n')}',
                      );
                }
              },
              mode: mode,
              onModeChanged: (next) =>
                  ref.read(sqlModeProvider.notifier).state = next,
              onSettings: () => _openSettings(context),
            ),
            Expanded(
              child: Row(
                children: [
                  _CategoryRail(
                    active: _activeCategory,
                    hasPlugins: pluginEntries.isNotEmpty,
                    onSelect: (next) => setState(() => _activeCategory = next),
                  ),
                  _Palette(
                    category: _activeCategory,
                    runtime: runtime,
                    mode: mode,
                    localeCode: locale.languageCode,
                    width: _paletteWidth,
                    pluginEntries: pluginEntries,
                    onAdd: (type, defaults) => ref
                        .read(workspaceProvider.notifier)
                        .addTemplate(
                          type,
                          const Offset(120, 100),
                          defaults: defaults,
                        ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _paletteWidth = (_paletteWidth + details.delta.dx)
                              .clamp(200.0, 520.0);
                        });
                      },
                      child: Container(
                        width: 10,
                        color: Colors.transparent,
                        alignment: Alignment.center,
                        child: Container(
                          width: 2,
                          height: double.infinity,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _WorkspaceCanvas(
                      focusNode: _workspaceFocus,
                      transform: _transform,
                      paletteWidth: 72.0 + _paletteWidth,
                    ),
                  ),
                  _SqlRuntimePane(
                    sql: sql,
                    runtime: runtime,
                    localeCode: locale.languageCode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _maybeAutosave(int revision) async {
    if (revision == _lastAutosaveRevision) return;
    _lastAutosaveRevision = revision;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 550), () async {
      final support = await getApplicationSupportDirectory();
      final autosave = File(
        '${support.path}/nodeql_autosave_${_activeProjectId}.nodeql',
      );
      await autosave.writeAsString(jsonEncode(_projectEnvelope()), flush: true);
    });
  }

  Future<void> _restoreAutosave() async {
    await _loadProjectRegistry();
    await _syncRecentProjectsToNativeMenu();
    final active = _recentProjects
        .where((p) => p['id'] == _activeProjectId)
        .toList(growable: false);
    if (active.isNotEmpty) {
      _activeProjectName = '${active.first['name'] ?? 'Untitled'}';
      _activeProjectPath = active.first['path'] as String?;
      if (_activeProjectPath != null) {
        try {
          if (await File(_activeProjectPath!).exists()) {
            final source = await File(_activeProjectPath!).readAsString();
            if (source.trim().isNotEmpty) {
              await _loadProjectPayload(source);
              return;
            }
          }
        } catch (_) {}
      }
    }
    final support = await getApplicationSupportDirectory();
    final autosave = File(
      '${support.path}/nodeql_autosave_${_activeProjectId}.nodeql',
    );
    final legacySqpAutosave = File(
      '${support.path}/nodeql_autosave_${_activeProjectId}.sqp',
    );
    final legacyScratchQlAutosave = File(
      '${support.path}/scratchql_autosave_${_activeProjectId}.scratchql',
    );
    final legacyScratchQlSqpAutosave = File(
      '${support.path}/scratchql_autosave_${_activeProjectId}.sqp',
    );
    final sourceFile = await autosave.exists()
        ? autosave
        : (await legacySqpAutosave.exists()
              ? legacySqpAutosave
              : (await legacyScratchQlAutosave.exists()
                    ? legacyScratchQlAutosave
                    : (await legacyScratchQlSqpAutosave.exists()
                          ? legacyScratchQlSqpAutosave
                          : null)));
    if (sourceFile == null) return;
    final source = await sourceFile.readAsString();
    if (source.trim().isEmpty) return;
    await _loadProjectPayload(source);
    await _syncRecentProjectsToNativeMenu();
  }

  Future<void> _newProject(BuildContext context) async {
    final createDb = ValueNotifier<bool>(false);
    final dbName = TextEditingController(text: 'nodeql_project');
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Project'),
        content: ValueListenableBuilder<bool>(
          valueListenable: createDb,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Reset current canvas?'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: value,
                    onChanged: (v) => createDb.value = v ?? false,
                  ),
                  const Expanded(child: Text('Create empty SQLite DB')),
                ],
              ),
              if (value)
                TextField(
                  controller: dbName,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Database name',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (yes == true) {
      ref.read(workspaceProvider.notifier).resetWithRoot();
      if (createDb.value) {
        try {
          await ref
              .read(sqlRuntimeProvider.notifier)
              .createEmptyDatabase(preferredName: dbName.text);
        } catch (e) {
          ref
              .read(sqlRuntimeProvider.notifier)
              .setMessage('Failed to create DB: $e');
        }
      }
      setState(() {
        _activeProjectPath = null;
        _activeProjectId = 'project_${DateTime.now().millisecondsSinceEpoch}';
        _activeProjectName = 'Untitled';
      });
      await _saveProjectRegistry();
      await _syncRecentProjectsToNativeMenu();
    }
    dbName.dispose();
    createDb.dispose();
  }

  Future<void> _saveProjectAs(BuildContext context) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save NodeQL project',
      fileName: 'project.nodeql',
      type: FileType.custom,
      allowedExtensions: <String>['nodeql'],
    );
    if (path == null) return;
    await File(path).writeAsString(jsonEncode(_projectEnvelope()), flush: true);
    final sandboxPath = await _cacheProjectForSandbox(path);
    setState(() {
      _activeProjectPath = sandboxPath;
      _activeProjectId = 'project_${DateTime.now().millisecondsSinceEpoch}';
      _activeProjectName = _projectNameFromPath(path);
      _upsertRecentProject();
    });
    await _saveProjectRegistry();
    await _syncRecentProjectsToNativeMenu();
  }

  Future<void> _saveProject(BuildContext context) async {
    final path = _activeProjectPath;
    if (path == null) {
      await _saveProjectAs(context);
      return;
    }

    await File(path).writeAsString(jsonEncode(_projectEnvelope()), flush: true);
    _upsertRecentProject();
    await _saveProjectRegistry();
    await _syncRecentProjectsToNativeMenu();
  }

  Future<void> _openProject(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open NodeQL project',
      type: FileType.custom,
      allowedExtensions: <String>['nodeql', 'scratchql', 'sqlq', 'sqp'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final sandboxPath = await _cacheProjectForSandbox(path);
    final source = await File(sandboxPath).readAsString();
    await _loadProjectPayload(source);
    setState(() {
      _activeProjectPath = sandboxPath;
      final existing = _recentProjects
          .where((p) => p['path'] == sandboxPath)
          .toList();
      _activeProjectId = existing.isEmpty
          ? 'project_${DateTime.now().millisecondsSinceEpoch}'
          : '${existing.first['id']}';
      _activeProjectName = _projectNameFromPath(path);
      _upsertRecentProject();
    });
    await _saveProjectRegistry();
    await _syncRecentProjectsToNativeMenu();
  }

  Future<void> _openSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Settings'),
        content: Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(nodeQlThemeProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<NodeQlTheme>(
                  value: NodeQlTheme.dark,
                  groupValue: current,
                  onChanged: (v) =>
                      ref.read(nodeQlThemeProvider.notifier).setTheme(v!),
                  title: const Text('Dark Mode'),
                ),
                RadioListTile<NodeQlTheme>(
                  value: NodeQlTheme.midnight,
                  groupValue: current,
                  onChanged: (v) =>
                      ref.read(nodeQlThemeProvider.notifier).setTheme(v!),
                  title: const Text('Midnight Tech'),
                ),
                RadioListTile<NodeQlTheme>(
                  value: NodeQlTheme.matrix,
                  groupValue: current,
                  onChanged: (v) =>
                      ref.read(nodeQlThemeProvider.notifier).setTheme(v!),
                  title: const Text('Matrix/Hacker'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(pluginPaletteProvider.notifier).reload(),
                  child: const Text('Reload Plugins'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _projectNameFromPath(String path) {
    final chunks = path.split(Platform.pathSeparator);
    final file = chunks.isEmpty ? path : chunks.last;
    if (file.endsWith('.nodeql')) {
      return file.substring(0, file.length - '.nodeql'.length);
    }
    if (file.endsWith('.scratchql')) {
      return file.substring(0, file.length - '.scratchql'.length);
    }
    if (file.endsWith('.sqlq')) return file.substring(0, file.length - 5);
    if (file.endsWith('.sqp')) return file.substring(0, file.length - 4);
    return file;
  }

  Future<String> _cacheProjectForSandbox(String sourcePath) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/nodeql_projects');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final filename = sourcePath.split(Platform.pathSeparator).last;
    final target = File('${dir.path}/$filename');
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Map<String, dynamic> _projectEnvelope() {
    final workspace =
        jsonDecode(ref.read(workspaceProvider.notifier).toJsonString())
            as Map<String, dynamic>;
    final runtime = ref.read(sqlRuntimeProvider);
    final mode = ref.read(sqlModeProvider);
    final locale = ref.read(localeControllerProvider);
    final theme = ref.read(nodeQlThemeProvider);
    return <String, dynamic>{
      'format': 'nodeql_project_v2',
      'version': 2,
      'workspace': workspace,
      'runtime': <String, dynamic>{'dbPath': runtime.dbPath},
      'ui': <String, dynamic>{
        'mode': mode.name,
        'locale': locale.languageCode,
        'theme': theme.name,
      },
    };
  }

  Future<void> _loadProjectPayload(String source) async {
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {}

    if (decoded == null || !_isProjectEnvelopeFormat(decoded['format'])) {
      ref.read(workspaceProvider.notifier).loadFromJsonString(source);
      return;
    }

    final workspace =
        (decoded['workspace'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    ref
        .read(workspaceProvider.notifier)
        .loadFromJsonString(jsonEncode(workspace));

    final runtime = decoded['runtime'] as Map<String, dynamic>? ?? {};
    final dbPath = runtime['dbPath'] as String?;
    if (dbPath != null && dbPath.trim().isNotEmpty) {
      await ref.read(sqlRuntimeProvider.notifier).attachDatabasePath(dbPath);
    }
  }

  bool _isProjectEnvelopeFormat(Object? format) {
    return format == 'nodeql_project_v2' || format == 'scratchql_project_v2';
  }

  void _upsertRecentProject() {
    final idx = _recentProjects.indexWhere((p) => p['id'] == _activeProjectId);
    final item = <String, dynamic>{
      'id': _activeProjectId,
      'name': _activeProjectName,
      'path': _activeProjectPath,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (idx >= 0) {
      _recentProjects[idx] = item;
    } else {
      _recentProjects.insert(0, item);
    }
  }

  Future<File> _registryFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/nodeql_projects.json');
  }

  Future<void> _loadProjectRegistry() async {
    final file = await _registryFile();
    if (!await file.exists()) return;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _activeProjectId = '${decoded['activeProjectId'] ?? 'default'}';
    final projects = (decoded['projects'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    _recentProjects = projects;
  }

  Future<void> _saveProjectRegistry() async {
    final file = await _registryFile();
    final payload = <String, dynamic>{
      'activeProjectId': _activeProjectId,
      'projects': _recentProjects,
      'version': 1,
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<void> _switchProject(String projectId) async {
    final target = _recentProjects
        .where((p) => p['id'] == projectId)
        .toList(growable: false);
    if (target.isEmpty) return;
    final path = target.first['path'] as String?;
    if (path == null || !await File(path).exists()) return;
    final source = await File(path).readAsString();
    await _loadProjectPayload(source);
    setState(() {
      _activeProjectId = projectId;
      _activeProjectName = '${target.first['name']}';
      _activeProjectPath = path;
    });
    await _saveProjectRegistry();
    await _syncRecentProjectsToNativeMenu();
  }

  Future<void> _syncRecentProjectsToNativeMenu() async {
    try {
      await _menuChannel.invokeMethod<void>('setRecentProjects', {
        'items': _recentProjects
            .map((p) => {'id': '${p['id']}', 'name': '${p['name']}'})
            .toList(growable: false),
      });
    } catch (_) {}
  }

  Future<void> _handleNativeMenuAction(MethodCall call) async {
    switch (call.method) {
      case 'newProject':
        await _newProject(context);
        break;
      case 'openProject':
        await _openProject(context);
        break;
      case 'saveProject':
        await _saveProject(context);
        break;
      case 'saveProjectAs':
        await _saveProjectAs(context);
        break;
      case 'undo':
        ref.read(workspaceProvider.notifier).undo();
        break;
      case 'redo':
        ref.read(workspaceProvider.notifier).redo();
        break;
      case 'deleteSelected':
        await _handleDeleteWithRootConfirmation(context, ref);
        break;
      case 'recentProject':
        final args = call.arguments as Map?;
        final id = args?['id'] as String?;
        if (id != null) {
          await _switchProject(id);
        }
        break;
      default:
        break;
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.l10n,
    required this.localeCode,
    required this.onLocale,
    required this.onPickDb,
    required this.onExecuteGuarded,
    required this.mode,
    required this.onModeChanged,
    required this.onSettings,
  });

  final AppLocalizations l10n;
  final String localeCode;
  final ValueChanged<String> onLocale;
  final VoidCallback onPickDb;
  final VoidCallback onExecuteGuarded;
  final SqlAbstractionMode mode;
  final ValueChanged<SqlAbstractionMode> onModeChanged;
  final VoidCallback onSettings;

  String _localizedUi(String key, String localeCode) {
    final map = <String, Map<String, String>>{
      'mount_db': {
        'de': 'DB laden',
        'en': 'Mount .db',
        'fr': 'Monter .db',
        'es': 'Montar .db',
      },
      'run_sql': {
        'de': 'SQL ausführen',
        'en': 'Run SQL',
        'fr': 'Exécuter SQL',
        'es': 'Ejecutar SQL',
      },
    };
    return map[key]?[localeCode] ?? map[key]?['en'] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF0B1220),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    l10n.appName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: onPickDb,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFE2E8F0),
                    ),
                    child: Text(_localizedUi('mount_db', localeCode)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onExecuteGuarded,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_localizedUi('run_sql', localeCode)),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<SqlAbstractionMode>(
                    segments: const [
                      ButtonSegment(
                        value: SqlAbstractionMode.simple,
                        label: Text('Simple'),
                      ),
                      ButtonSegment(
                        value: SqlAbstractionMode.advanced,
                        label: Text('Advanced'),
                      ),
                    ],
                    selected: <SqlAbstractionMode>{mode},
                    onSelectionChanged: (selection) =>
                        onModeChanged(selection.first),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: localeCode,
                    dropdownColor: const Color(0xFF0F172A),
                    items: supportedLanguages
                        .map(
                          (l) => DropdownMenuItem(
                            value: l.code,
                            child: Text(
                              l.nativeName,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onLocale(v);
                    },
                  ),
                  IconButton(
                    onPressed: onSettings,
                    color: const Color(0xFFE2E8F0),
                    icon: const Icon(Icons.settings),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum SqlPaletteCategory { dql, dml, ddl, dcl, txn, plugins }

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.active,
    required this.onSelect,
    required this.hasPlugins,
  });

  final SqlPaletteCategory active;
  final ValueChanged<SqlPaletteCategory> onSelect;
  final bool hasPlugins;

  @override
  Widget build(BuildContext context) {
    final entries = <(SqlPaletteCategory, IconData, Color)>[
      (SqlPaletteCategory.dql, Icons.search, ScratchPalette.motion),
      (SqlPaletteCategory.dml, Icons.edit_note, ScratchPalette.control),
      (SqlPaletteCategory.ddl, Icons.schema, ScratchPalette.operators),
      (SqlPaletteCategory.dcl, Icons.lock_open, ScratchPalette.events),
      (SqlPaletteCategory.txn, Icons.account_tree, ScratchPalette.variables),
      if (hasPlugins)
        (SqlPaletteCategory.plugins, Icons.extension, ScratchPalette.myBlocks),
    ];

    return SizedBox(
      width: 72,
      child: ListView(
        children: entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.all(8),
                child: InkWell(
                  onTap: () => onSelect(e.$1),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: e.$3.withValues(alpha: active == e.$1 ? 1 : 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(e.$2, color: Colors.white),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Palette extends StatefulWidget {
  const _Palette({
    required this.category,
    required this.runtime,
    required this.mode,
    required this.localeCode,
    required this.width,
    required this.pluginEntries,
    required this.onAdd,
  });

  final SqlPaletteCategory category;
  final SqlRuntimeState runtime;
  final SqlAbstractionMode mode;
  final String localeCode;
  final double width;
  final List<PluginPaletteEntry> pluginEntries;
  final void Function(BlockType type, Map<String, dynamic>? defaults) onAdd;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tileWidth = (widget.width - 32).clamp(160.0, 500.0);
    final pluginByType = <BlockType, PluginPaletteEntry>{
      for (final p in widget.pluginEntries) p.blockType: p,
    };
    final query = _query.trim().toLowerCase();
    final sourceBlocks = query.isEmpty
        ? _blocksForCategory(widget.category)
        : _allSearchableBlocks();
    final blocks = query.isEmpty
        ? sourceBlocks
        : sourceBlocks
              .where((block) {
                final description = _commandHelp(block.$1, widget.localeCode);
                return block.$2.toLowerCase().contains(query) ||
                    description.toLowerCase().contains(query) ||
                    block.$1.name.toLowerCase().contains(query);
              })
              .toList(growable: false);

    return SizedBox(
      width: widget.width,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                hintText: widget.localeCode == 'de'
                    ? 'Befehl suchen'
                    : 'Search command',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E293B)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF60A5FA)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Row(
              children: [
                Text(
                  query.isEmpty
                      ? _categoryTitle(widget.category, widget.localeCode)
                      : (widget.localeCode == 'de'
                            ? 'Suchergebnisse'
                            : 'Search results'),
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${blocks.length}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: blocks
                  .map(
                    (block) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PaletteCard(
                        type: block.$1,
                        label: block.$2,
                        description: _commandHelp(block.$1, widget.localeCode),
                        color: _colorForType(block.$1),
                        node: _templateNode(block.$1),
                        width: tileWidth,
                        onAdd: () => widget.onAdd(
                          block.$1,
                          pluginByType[block.$1]?.defaults,
                        ),
                        onHelp: () => _showCommandHelp(context, block.$1),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<(BlockType, String)> _blocksForCategory(SqlPaletteCategory category) {
    String lbl(BlockType type) =>
        sqlLabelFor(type, widget.mode, const {}, widget.localeCode);
    return switch (category) {
      SqlPaletteCategory.dql => <(BlockType, String)>[
        (BlockType.eventGreenFlag, lbl(BlockType.eventGreenFlag)),
        (BlockType.sqlSelect, lbl(BlockType.sqlSelect)),
        (BlockType.sqlWhere, lbl(BlockType.sqlWhere)),
        (BlockType.sqlJoin, lbl(BlockType.sqlJoin)),
        (BlockType.sqlGroupBy, lbl(BlockType.sqlGroupBy)),
        (BlockType.sqlHaving, lbl(BlockType.sqlHaving)),
        (BlockType.sqlOrderBy, lbl(BlockType.sqlOrderBy)),
        (BlockType.sqlInnerJoin, lbl(BlockType.sqlInnerJoin)),
        (BlockType.sqlLeftJoin, lbl(BlockType.sqlLeftJoin)),
        (BlockType.sqlRightJoin, lbl(BlockType.sqlRightJoin)),
        (BlockType.sqlFullJoin, lbl(BlockType.sqlFullJoin)),
        (BlockType.sqlCrossJoin, lbl(BlockType.sqlCrossJoin)),
        (BlockType.sqlNaturalJoin, lbl(BlockType.sqlNaturalJoin)),
        (BlockType.sqlSubqueryIn, lbl(BlockType.sqlSubqueryIn)),
        (BlockType.sqlSubqueryAny, lbl(BlockType.sqlSubqueryAny)),
        (BlockType.sqlSubqueryAll, lbl(BlockType.sqlSubqueryAll)),
        (BlockType.sqlCount, lbl(BlockType.sqlCount)),
        (BlockType.sqlSum, lbl(BlockType.sqlSum)),
        (BlockType.sqlAvg, lbl(BlockType.sqlAvg)),
        (BlockType.sqlMin, lbl(BlockType.sqlMin)),
        (BlockType.sqlMax, lbl(BlockType.sqlMax)),
        (BlockType.sqlConcat, lbl(BlockType.sqlConcat)),
        (BlockType.sqlSubstring, lbl(BlockType.sqlSubstring)),
        (BlockType.sqlLength, lbl(BlockType.sqlLength)),
        (BlockType.sqlUpper, lbl(BlockType.sqlUpper)),
        (BlockType.sqlLower, lbl(BlockType.sqlLower)),
        (BlockType.sqlTrim, lbl(BlockType.sqlTrim)),
        (BlockType.sqlLeft, lbl(BlockType.sqlLeft)),
        (BlockType.sqlRight, lbl(BlockType.sqlRight)),
        (BlockType.sqlReplace, lbl(BlockType.sqlReplace)),
        (BlockType.sqlCurrentDate, lbl(BlockType.sqlCurrentDate)),
        (BlockType.sqlCurrentTime, lbl(BlockType.sqlCurrentTime)),
        (BlockType.sqlCurrentTimestamp, lbl(BlockType.sqlCurrentTimestamp)),
        (BlockType.sqlDatePart, lbl(BlockType.sqlDatePart)),
        (BlockType.sqlDateAdd, lbl(BlockType.sqlDateAdd)),
        (BlockType.sqlDateSub, lbl(BlockType.sqlDateSub)),
        (BlockType.sqlExtract, lbl(BlockType.sqlExtract)),
        (BlockType.sqlToChar, lbl(BlockType.sqlToChar)),
        (BlockType.sqlTimestampDiff, lbl(BlockType.sqlTimestampDiff)),
        (BlockType.sqlDateDiff, lbl(BlockType.sqlDateDiff)),
        (BlockType.sqlCase, lbl(BlockType.sqlCase)),
        (BlockType.sqlIf, lbl(BlockType.sqlIf)),
        (BlockType.sqlCoalesce, lbl(BlockType.sqlCoalesce)),
        (BlockType.sqlNullIf, lbl(BlockType.sqlNullIf)),
        (BlockType.sqlFrom, lbl(BlockType.sqlFrom)),
      ],
      SqlPaletteCategory.dml => <(BlockType, String)>[
        (BlockType.sqlInsert, lbl(BlockType.sqlInsert)),
        (BlockType.sqlUpdate, lbl(BlockType.sqlUpdate)),
        (BlockType.sqlDelete, lbl(BlockType.sqlDelete)),
      ],
      SqlPaletteCategory.ddl => <(BlockType, String)>[
        (BlockType.sqlCreateTable, lbl(BlockType.sqlCreateTable)),
        (BlockType.sqlAlterTable, lbl(BlockType.sqlAlterTable)),
        (BlockType.sqlTruncate, lbl(BlockType.sqlTruncate)),
        (BlockType.sqlDropTable, lbl(BlockType.sqlDropTable)),
        (BlockType.sqlGrant, lbl(BlockType.sqlGrant)),
        (BlockType.sqlRevoke, lbl(BlockType.sqlRevoke)),
      ],
      SqlPaletteCategory.dcl => <(BlockType, String)>[
        (BlockType.sqlGrant, lbl(BlockType.sqlGrant)),
        (BlockType.sqlRevoke, lbl(BlockType.sqlRevoke)),
      ],
      SqlPaletteCategory.txn => <(BlockType, String)>[
        (BlockType.sqlCommit, lbl(BlockType.sqlCommit)),
        (BlockType.sqlRollback, lbl(BlockType.sqlRollback)),
        (BlockType.sqlSavepoint, lbl(BlockType.sqlSavepoint)),
        (
          BlockType.sqlRollbackToSavepoint,
          lbl(BlockType.sqlRollbackToSavepoint),
        ),
        (BlockType.sqlSetTransaction, lbl(BlockType.sqlSetTransaction)),
        (BlockType.sqlUnion, lbl(BlockType.sqlUnion)),
        (BlockType.sqlIntersect, lbl(BlockType.sqlIntersect)),
        (BlockType.sqlExcept, lbl(BlockType.sqlExcept)),
      ],
      SqlPaletteCategory.plugins =>
        widget.pluginEntries
            .map(
              (entry) => (
                entry.blockType,
                entry.labelOverride ?? lbl(entry.blockType),
              ),
            )
            .toList(growable: false),
    };
  }

  List<(BlockType, String)> _allSearchableBlocks() {
    final seen = <BlockType>{};
    final all = <(BlockType, String)>[];
    for (final category in SqlPaletteCategory.values) {
      if (category == SqlPaletteCategory.plugins &&
          widget.pluginEntries.isEmpty) {
        continue;
      }
      for (final block in _blocksForCategory(category)) {
        if (seen.add(block.$1)) all.add(block);
      }
    }
    return all;
  }

  String _commandHelp(BlockType type, String localeCode) {
    final de = localeCode == 'de';
    switch (type) {
      case BlockType.eventGreenFlag:
        return de
            ? 'Startet die SQL-Abfragekette im Workspace.'
            : 'Starts the SQL query chain in the workspace.';
      case BlockType.motionMove:
        return de
            ? 'Legacy-Block: bewegt ein Objekt (nicht SQL-spezifisch).'
            : 'Legacy block: moves an object (not SQL specific).';
      case BlockType.motionTurn:
        return de
            ? 'Legacy-Block: dreht ein Objekt (nicht SQL-spezifisch).'
            : 'Legacy block: rotates an object (not SQL specific).';
      case BlockType.controlRepeat:
        return de
            ? 'Legacy-Block: wiederholt enthaltene Blöcke mehrfach.'
            : 'Legacy block: repeats nested blocks multiple times.';
      case BlockType.controlForever:
        return de
            ? 'Legacy-Block: führt enthaltene Blöcke endlos aus.'
            : 'Legacy block: runs nested blocks forever.';
      case BlockType.operatorAdd:
        return de
            ? 'Legacy-Operator für einfache Rechenoperationen.'
            : 'Legacy operator for basic arithmetic.';
      case BlockType.variableSet:
        return de
            ? 'Legacy-Block: setzt einen Variablenwert.'
            : 'Legacy block: sets a variable value.';
      case BlockType.sqlSelect:
        return de
            ? 'Ruft Daten aus einer Datenbank ab. Du wählst Spalten und eine Tabelle aus.'
            : 'Retrieves data from a database. Choose columns and a source table.';
      case BlockType.sqlColumn:
        return de
            ? 'Definiert eine einzelne Spalte oder Ausdruck.'
            : 'Defines a single column or expression.';
      case BlockType.sqlFrom:
        return de
            ? 'Legt fest, aus welcher Tabelle gelesen wird.'
            : 'Defines which table to read from.';
      case BlockType.sqlWhere:
        return de
            ? 'Filtert Zeilen anhand einer Bedingung, z. B. nur Kunden mit Alter > 30.'
            : 'Filters rows by a condition, for example customers with age > 30.';
      case BlockType.sqlOrderBy:
        return de
            ? 'Sortiert die Ergebnisliste nach einer Spalte auf- oder absteigend.'
            : 'Sorts the result set by a column in ascending or descending order.';
      case BlockType.sqlJoin:
        return de
            ? 'Verknüpft Tabellen über passende Werte, damit zusammengehörige Daten in einer Abfrage erscheinen.'
            : 'Combines tables through matching values so related data appears in one query.';
      case BlockType.sqlInnerJoin:
        return de
            ? 'Gibt nur Zeilen zurück, bei denen beide Tabellen passende Werte haben.'
            : 'Returns only rows where both tables have matching values.';
      case BlockType.sqlLeftJoin:
        return de
            ? 'Gibt alle Zeilen der linken Tabelle zurück und ergänzt passende Zeilen der rechten Tabelle.'
            : 'Returns all rows from the left table and matching rows from the right table.';
      case BlockType.sqlRightJoin:
        return de
            ? 'Gibt alle Zeilen der rechten Tabelle zurück und ergänzt passende Zeilen der linken Tabelle.'
            : 'Returns all rows from the right table and matching rows from the left table.';
      case BlockType.sqlFullJoin:
        return de
            ? 'Gibt alle Zeilen beider Tabellen zurück, wenn auf einer Seite ein Treffer existiert.'
            : 'Returns all rows when there is a match in either table.';
      case BlockType.sqlCrossJoin:
        return de
            ? 'Kombiniert jede Zeile der ersten Tabelle mit jeder Zeile der zweiten Tabelle.'
            : 'Combines every row from the first table with every row from the second table.';
      case BlockType.sqlSelfJoin:
        return de
            ? 'Verknüpft eine Tabelle mit sich selbst, z. B. für Hierarchien oder Vergleiche.'
            : 'Joins a table with itself, useful for hierarchies or comparisons.';
      case BlockType.sqlNaturalJoin:
        return de
            ? 'Verknüpft Tabellen automatisch über Spalten mit gleichem Namen.'
            : 'Automatically joins tables through columns with the same name.';
      case BlockType.sqlGroupBy:
        return de
            ? 'Gruppiert Zeilen nach Spaltenwerten und wird oft mit COUNT, SUM oder AVG genutzt.'
            : 'Groups rows by column values and is often used with COUNT, SUM, or AVG.';
      case BlockType.sqlHaving:
        return de
            ? 'Filtert gruppierte Ergebnisse nach einer Bedingung, also nach GROUP BY.'
            : 'Filters grouped results by a condition after GROUP BY.';
      case BlockType.sqlUnion:
        return de
            ? 'Vereint Ergebnisse aus zwei Abfragen (Duplikate entfernt).'
            : 'Combines results of two queries (deduplicated).';
      case BlockType.sqlIntersect:
        return de
            ? 'Behält nur Treffer, die in beiden Abfragen vorkommen.'
            : 'Keeps only rows present in both queries.';
      case BlockType.sqlExcept:
        return de
            ? 'Entfernt Treffer der zweiten Abfrage aus der ersten.'
            : 'Removes rows of the second query from the first.';
      case BlockType.sqlSubqueryIn:
        return de
            ? 'Prüft, ob ein Wert in den Ergebnissen einer Unterabfrage vorkommt.'
            : 'Checks whether a value matches any value returned by a subquery.';
      case BlockType.sqlSubqueryAny:
        return de
            ? 'Vergleicht einen Wert mit irgendeinem Ergebnis einer Unterabfrage.'
            : 'Compares a value to any value returned by a subquery.';
      case BlockType.sqlSubqueryAll:
        return de
            ? 'Vergleicht einen Wert mit allen Ergebnissen einer Unterabfrage.'
            : 'Compares a value to all values returned by a subquery.';
      case BlockType.sqlCount:
        return de
            ? 'Zählt Zeilen oder nicht-leere Werte.'
            : 'Counts rows or non-null values.';
      case BlockType.sqlSum:
        return de
            ? 'Bildet die Summe numerischer Werte.'
            : 'Calculates the sum of numeric values.';
      case BlockType.sqlAvg:
        return de
            ? 'Berechnet den Durchschnitt numerischer Werte.'
            : 'Calculates the average of numeric values.';
      case BlockType.sqlMin:
        return de
            ? 'Gibt den kleinsten Wert zurück.'
            : 'Returns the smallest value.';
      case BlockType.sqlMax:
        return de
            ? 'Gibt den größten Wert zurück.'
            : 'Returns the largest value.';
      case BlockType.sqlConcat:
        return de
            ? 'Verkettet Texte zu einem String.'
            : 'Concatenates text values into one string.';
      case BlockType.sqlSubstring:
        return de
            ? 'Schneidet einen Textausschnitt aus einem String.'
            : 'Extracts a substring from text.';
      case BlockType.sqlLength:
        return de
            ? 'Gibt die Länge eines Textes zurück.'
            : 'Returns the length of a string.';
      case BlockType.sqlUpper:
        return de
            ? 'Wandelt Text in Großbuchstaben um.'
            : 'Converts text to uppercase.';
      case BlockType.sqlLower:
        return de
            ? 'Wandelt Text in Kleinbuchstaben um.'
            : 'Converts text to lowercase.';
      case BlockType.sqlTrim:
        return de
            ? 'Entfernt Leerzeichen am Anfang und Ende.'
            : 'Removes leading and trailing spaces.';
      case BlockType.sqlLeft:
        return de
            ? 'Liest die linken Zeichen eines Textes.'
            : 'Returns left-most characters of a string.';
      case BlockType.sqlRight:
        return de
            ? 'Liest die rechten Zeichen eines Textes.'
            : 'Returns right-most characters of a string.';
      case BlockType.sqlReplace:
        return de
            ? 'Ersetzt Textteile durch andere Werte.'
            : 'Replaces parts of a text value.';
      case BlockType.sqlCurrentDate:
        return de ? 'Liefert das aktuelle Datum.' : 'Returns the current date.';
      case BlockType.sqlCurrentTime:
        return de
            ? 'Liefert die aktuelle Uhrzeit.'
            : 'Returns the current time.';
      case BlockType.sqlCurrentTimestamp:
        return de
            ? 'Liefert aktuelles Datum und aktuelle Uhrzeit als Zeitstempel.'
            : 'Returns the current date and time as a timestamp.';
      case BlockType.sqlDatePart:
        return de
            ? 'Liest einen Teil eines Datums (z. B. Jahr/Monat).'
            : 'Extracts a date part (e.g. year/month).';
      case BlockType.sqlDateAdd:
        return de ? 'Addiert Zeit auf ein Datum.' : 'Adds time to a date.';
      case BlockType.sqlDateSub:
        return de
            ? 'Zieht Zeit von einem Datum ab.'
            : 'Subtracts time from a date.';
      case BlockType.sqlExtract:
        return de
            ? 'Extrahiert Datum-/Zeit-Komponenten aus einem Wert.'
            : 'Extracts date/time components from a value.';
      case BlockType.sqlToChar:
        return de ? 'Formatiert Werte als Text.' : 'Formats values as text.';
      case BlockType.sqlTimestampDiff:
        return de
            ? 'Berechnet Differenz zwischen zwei Zeitstempeln.'
            : 'Calculates difference between two timestamps.';
      case BlockType.sqlDateDiff:
        return de
            ? 'Berechnet Differenz zwischen zwei Datumswerten.'
            : 'Calculates difference between two dates.';
      case BlockType.sqlCase:
        return de
            ? 'Mehrfach-Bedingung: wenn/dann/sonst.'
            : 'Multi-branch condition: when/then/else.';
      case BlockType.sqlIf:
        return de
            ? 'Einfache Bedingung mit zwei Ergebnissen.'
            : 'Simple condition with two outcomes.';
      case BlockType.sqlCoalesce:
        return de
            ? 'Nimmt den ersten nicht-leeren Wert.'
            : 'Returns the first non-null value.';
      case BlockType.sqlNullIf:
        return de
            ? 'Gibt NULL zurück, wenn zwei Werte gleich sind.'
            : 'Returns NULL when two values are equal.';
      case BlockType.sqlInsert:
        return de
            ? 'Fügt neue Datensätze in eine Tabelle ein.'
            : 'Adds new records to a table.';
      case BlockType.sqlUpdate:
        return de
            ? 'Ändert bestehende Datensätze in einer Tabelle.'
            : 'Modifies existing records in a table.';
      case BlockType.sqlDelete:
        return de
            ? 'Entfernt Datensätze aus einer Tabelle, optional per Bedingung.'
            : 'Removes records from a table, optionally with a condition.';
      case BlockType.sqlCreateTable:
        return de
            ? 'Erstellt eine neue Tabelle oder andere Datenbankobjekte.'
            : 'Creates a new table or other database objects.';
      case BlockType.sqlAlterTable:
        return de
            ? 'Fügt Spalten hinzu, löscht sie oder ändert Spalten in einer bestehenden Tabelle.'
            : 'Adds, deletes, or modifies columns in an existing table.';
      case BlockType.sqlTruncate:
        return de
            ? 'Löscht alle Daten in einer Tabelle, behält aber die Tabelle selbst.'
            : 'Deletes all data inside a table while keeping the table itself.';
      case BlockType.sqlDropTable:
        return de
            ? 'Löscht eine bestehende Tabelle dauerhaft aus der Datenbank.'
            : 'Drops an existing table from the database.';
      case BlockType.sqlGrant:
        return de
            ? 'Gibt Benutzern oder Rollen bestimmte Rechte, z. B. SELECT oder INSERT.'
            : 'Gives specific privileges to users or roles, such as SELECT or INSERT.';
      case BlockType.sqlRevoke:
        return de
            ? 'Entzieht Rechte, die Benutzern oder Rollen vorher gegeben wurden.'
            : 'Takes away privileges previously granted to users or roles.';
      case BlockType.sqlCommit:
        return de
            ? 'Speichert alle Änderungen der aktuellen Transaktion.'
            : 'Persists changes of the current transaction.';
      case BlockType.sqlRollback:
        return de
            ? 'Verwirft Änderungen der aktuellen Transaktion.'
            : 'Discards changes of the current transaction.';
      case BlockType.sqlSavepoint:
        return de
            ? 'Setzt einen Zwischenstand innerhalb einer Transaktion.'
            : 'Creates a checkpoint inside a transaction.';
      case BlockType.sqlRollbackToSavepoint:
        return de
            ? 'Springt auf einen gesetzten Zwischenstand zurück.'
            : 'Rolls back to a defined transaction checkpoint.';
      case BlockType.sqlSetTransaction:
        return de
            ? 'Setzt Eigenschaften der aktuellen Transaktion.'
            : 'Sets properties of the current transaction.';
      case BlockType.sqlLoop:
        return de
            ? 'Führt enthaltene SQL-Blöcke wiederholt aus.'
            : 'Repeats execution of nested SQL blocks.';
    }
  }

  Future<void> _showCommandHelp(BuildContext context, BlockType type) async {
    final de = widget.localeCode == 'de';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          de ? 'Was macht dieser Block?' : 'What does this block do?',
        ),
        content: Text(_commandHelp(type, widget.localeCode)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _categoryTitle(SqlPaletteCategory category, String localeCode) {
    final de = localeCode == 'de';
    return switch (category) {
      SqlPaletteCategory.dql => de ? 'Daten abfragen' : 'Query data',
      SqlPaletteCategory.dml => de ? 'Daten bearbeiten' : 'Change data',
      SqlPaletteCategory.ddl => de ? 'Struktur bearbeiten' : 'Schema tools',
      SqlPaletteCategory.dcl => de ? 'Rechte verwalten' : 'Permissions',
      SqlPaletteCategory.txn =>
        de ? 'Transaktionen & Mengen' : 'Transactions & sets',
      SqlPaletteCategory.plugins => de ? 'Erweiterungen' : 'Extensions',
    };
  }

  BlockNode _templateNode(BlockType type) {
    switch (type) {
      case BlockType.sqlSelect:
        return OperatorBlock(
          id: 'tpl_sel',
          position: Offset.zero,
          operatorType: type,
        );
      case BlockType.eventGreenFlag:
        return EventBlock(id: 'tpl_evt', position: Offset.zero);
      case BlockType.sqlWhere:
      case BlockType.sqlOrderBy:
        return MotionBlock(
          id: 'tpl_mot',
          position: Offset.zero,
          motionType: type,
        );
      case BlockType.sqlLoop:
        return ControlBlock(
          id: 'tpl_ctl',
          position: Offset.zero,
          controlType: type,
        );
      default:
        return OperatorBlock(
          id: 'tpl_op',
          position: Offset.zero,
          operatorType: type,
        );
    }
  }

  Color _colorForType(BlockType type) {
    switch (type) {
      case BlockType.sqlSelect:
        return ScratchPalette.motion;
      case BlockType.eventGreenFlag:
        return ScratchPalette.events;
      case BlockType.sqlWhere:
      case BlockType.sqlOrderBy:
        return ScratchPalette.motion;
      case BlockType.sqlLoop:
        return ScratchPalette.control;
      case BlockType.sqlGroupBy:
      case BlockType.sqlJoin:
      case BlockType.sqlFrom:
      case BlockType.sqlColumn:
      case BlockType.sqlCreateTable:
      case BlockType.sqlDropTable:
        return ScratchPalette.operators;
      case BlockType.sqlInsert:
      case BlockType.sqlUpdate:
      case BlockType.sqlDelete:
        return ScratchPalette.variables;
      default:
        return ScratchPalette.operators;
    }
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.type,
    required this.label,
    required this.description,
    required this.color,
    required this.node,
    required this.width,
    required this.onAdd,
    required this.onHelp,
  });

  final BlockType type;
  final String label;
  final String description;
  final Color color;
  final BlockNode node;
  final double width;
  final VoidCallback onAdd;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final block = BlockShape(
      node: node,
      color: color,
      width: width,
      height: WorkspaceController.blockBaseHeight,
      label: label,
    );

    return Draggable<BlockType>(
      data: type,
      feedback: Material(color: Colors.transparent, child: block),
      child: GestureDetector(
        onTap: onAdd,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  block,
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Tooltip(
                      message: description,
                      child: InkWell(
                        onTap: onHelp,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceCanvas extends ConsumerWidget {
  const _WorkspaceCanvas({
    required this.focusNode,
    required this.transform,
    required this.paletteWidth,
  });

  final FocusNode focusNode;
  final TransformationController transform;
  final double paletteWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final controller = ref.read(workspaceProvider.notifier);
    transform.value = Matrix4.identity()
      ..translate(workspace.pan.dx, workspace.pan.dy)
      ..scale(workspace.scale);

    return DragTarget<BlockType>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final rb = context.findRenderObject() as RenderBox;
        final local = rb.globalToLocal(details.offset);
        controller.addTemplate(details.data, _toWorld(local));
      },
      builder: (context, _, __) => Focus(
        autofocus: true,
        focusNode: focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final keyboard = HardwareKeyboard.instance;
          final cmdOrCtrl = keyboard.isMetaPressed || keyboard.isControlPressed;
          if (cmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
            final redo = keyboard.isShiftPressed;
            if (redo) {
              ref.read(workspaceProvider.notifier).redo();
            } else {
              ref.read(workspaceProvider.notifier).undo();
            }
            return KeyEventResult.handled;
          }
          if (cmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
            ref.read(workspaceProvider.notifier).redo();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _handleDeleteWithRootConfirmation(context, ref);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _PointerWorkspaceLayer(
          workspace: workspace,
          transform: transform,
          paletteWidth: paletteWidth,
          focusNode: focusNode,
          child: Container(
            color: ScratchPalette.workspace,
            child: ClipRect(
              child: RepaintBoundary(
                child: Transform(
                  transform: transform.value,
                  alignment: Alignment.topLeft,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final block in controller.allBlocks())
                        Positioned(
                          left: block.position.dx,
                          top: block.position.dy,
                          child: _NodeView(
                            node: block,
                            highlighted:
                                workspace.highlightTargetId == block.id,
                            innerHighlighted:
                                workspace.highlightTargetId == block.id &&
                                (workspace.highlightZone == SnapZone.innerTop ||
                                    workspace.highlightZone ==
                                        SnapZone.innerBottom),
                            selected: workspace.selectedBlockIds.contains(
                              block.id,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _toWorld(Offset local) {
    final matrix = transform.value.clone()..invert();
    return MatrixUtils.transformPoint(matrix, local);
  }
}

Future<void> _handleDeleteWithRootConfirmation(
  BuildContext context,
  WidgetRef ref,
) async {
  final workspace = ref.read(workspaceProvider);
  final selectedIds = workspace.selectedBlockIds.isNotEmpty
      ? workspace.selectedBlockIds
      : (workspace.selectedBlockId == null
            ? const <String>{}
            : <String>{workspace.selectedBlockId!});
  if (selectedIds.isEmpty) return;
  final selectedRoots = workspace.roots
      .where((r) => selectedIds.contains(r.id))
      .toList(growable: false);
  final isRootEvent = selectedRoots.any(
    (r) => r.type == BlockType.eventGreenFlag,
  );

  if (!isRootEvent) {
    ref.read(workspaceProvider.notifier).deleteSelected();
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF111827),
      title: const Text(
        'Delete root script?',
        style: TextStyle(color: Colors.white),
      ),
      content: const Text(
        'This will remove the trigger and its attached chain.',
        style: TextStyle(color: Color(0xFFD1D5DB)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    ref.read(workspaceProvider.notifier).deleteSelected();
  }
}

class _PointerWorkspaceLayer extends ConsumerStatefulWidget {
  const _PointerWorkspaceLayer({
    required this.workspace,
    required this.transform,
    required this.paletteWidth,
    required this.focusNode,
    required this.child,
  });

  final WorkspaceState workspace;
  final TransformationController transform;
  final double paletteWidth;
  final FocusNode focusNode;
  final Widget child;

  @override
  ConsumerState<_PointerWorkspaceLayer> createState() =>
      _PointerWorkspaceLayerState();
}

class _PointerWorkspaceLayerState
    extends ConsumerState<_PointerWorkspaceLayer> {
  bool _rightPanning = false;
  bool _secondaryPending = false;
  bool _leftDraggingBlock = false;
  bool _leftMoved = false;
  bool _primaryPending = false;
  Offset? _primaryDownWorld;
  Offset? _primaryDownLocal;
  Offset? _secondaryDownWorld;
  Offset? _secondaryDownLocal;
  Offset? _secondaryDownGlobal;
  bool _marqueeSelecting = false;
  Rect? _marqueeRectLocal;
  double? _panZoomStartScale;
  double? _scaleGestureStartScale;

  @override
  Widget build(BuildContext context) {
    final engine = ref.read(workspaceProvider.notifier);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (event.kind == PointerDeviceKind.trackpad) return;
        final workspace = ref.read(workspaceProvider);
        final factor = (1 - event.scrollDelta.dy * 0.001).clamp(0.8, 1.2);
        engine.zoomAt(event.localPosition, workspace.scale * factor);
      },
      onPointerPanZoomStart: (event) {
        widget.focusNode.requestFocus();
        _panZoomStartScale = ref.read(workspaceProvider).scale;
      },
      onPointerPanZoomUpdate: (event) {
        final startScale =
            _panZoomStartScale ?? ref.read(workspaceProvider).scale;
        if ((event.scale - 1.0).abs() > 0.001) {
          engine.zoomAt(event.localPosition, startScale * event.scale);
        }
        if (event.panDelta.distanceSquared > 0) {
          engine.panBy(event.panDelta);
        }
      },
      onPointerPanZoomEnd: (_) {
        _panZoomStartScale = null;
      },
      onPointerDown: (event) {
        widget.focusNode.requestFocus();
        final world = _toWorld(event.localPosition);
        if (event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kSecondaryMouseButton) != 0) {
          _secondaryPending = true;
          _secondaryDownWorld = world;
          _secondaryDownLocal = event.localPosition;
          _secondaryDownGlobal = event.position;
          _rightPanning = false;
          _primaryPending = false;
          return;
        }

        if (event.kind == PointerDeviceKind.mouse &&
            (event.buttons & kPrimaryMouseButton) != 0) {
          _primaryPending = true;
          _primaryDownWorld = world;
          _primaryDownLocal = event.localPosition;
          _leftDraggingBlock = false;
          _leftMoved = false;
        }
      },
      onPointerMove: (event) {
        if (_secondaryPending &&
            !_rightPanning &&
            event.delta.distanceSquared > 9) {
          _rightPanning = true;
          _secondaryPending = false;
        }
        if (_rightPanning) {
          engine.panBy(event.delta);
          return;
        }
        if (_primaryPending &&
            !_leftDraggingBlock &&
            event.delta.distanceSquared > 9) {
          final downWorld = _primaryDownWorld ?? _toWorld(event.localPosition);
          final hitAtStart = engine.hitNodeAt(downWorld);
          if (hitAtStart != null) {
            engine.startDrag(downWorld);
            _leftDraggingBlock = ref.read(workspaceProvider).draggingId != null;
            _leftMoved = _leftDraggingBlock;
          } else {
            _marqueeSelecting = true;
            final start = _primaryDownLocal ?? event.localPosition;
            _marqueeRectLocal = Rect.fromPoints(start, event.localPosition);
          }
          _primaryPending = false;
        }
        if (_leftDraggingBlock) {
          if (event.delta.distanceSquared > 0) _leftMoved = true;
          engine.updateDrag(event.delta / ref.read(workspaceProvider).scale);
        } else if (_marqueeSelecting) {
          final start = _primaryDownLocal ?? event.localPosition;
          setState(() {
            _marqueeRectLocal = Rect.fromPoints(start, event.localPosition);
          });
        }
      },
      onPointerUp: (event) {
        if (_rightPanning) {
          _rightPanning = false;
          _secondaryPending = false;
          _secondaryDownWorld = null;
          _secondaryDownLocal = null;
          _secondaryDownGlobal = null;
          return;
        }
        if (_secondaryPending) {
          final world = _secondaryDownWorld ?? _toWorld(event.localPosition);
          final node = engine.hitNodeAt(world);
          if (node != null) {
            engine.selectAtWithMode(world);
            _showNodeContextMenu(event.position);
          }
          _secondaryPending = false;
          _secondaryDownWorld = null;
          _secondaryDownLocal = null;
          _secondaryDownGlobal = null;
          return;
        }
        if (_leftDraggingBlock) {
          final deleteByPalette = event.position.dx <= widget.paletteWidth;
          engine.endDrag(deleteDragged: deleteByPalette);
          _leftDraggingBlock = false;
          if (!_leftMoved) {
            engine.selectAt(_toWorld(event.localPosition));
          }
          _leftMoved = false;
          _primaryPending = false;
          _primaryDownWorld = null;
          _primaryDownLocal = null;
          return;
        }
        if (_marqueeSelecting) {
          final rect = _marqueeRectLocal;
          if (rect != null && rect.width > 4 && rect.height > 4) {
            final worldA = _toWorld(rect.topLeft);
            final worldB = _toWorld(rect.bottomRight);
            final worldRect = Rect.fromPoints(worldA, worldB);
            final append = HardwareKeyboard.instance.isShiftPressed;
            engine.selectInRect(worldRect, append: append);
          }
          setState(() {
            _marqueeSelecting = false;
            _marqueeRectLocal = null;
          });
          _primaryPending = false;
          _primaryDownWorld = null;
          _primaryDownLocal = null;
          return;
        }
        if (_primaryPending) {
          final append = HardwareKeyboard.instance.isShiftPressed;
          engine.selectAtWithMode(
            _toWorld(event.localPosition),
            append: append,
          );
          _primaryPending = false;
          _primaryDownWorld = null;
          _primaryDownLocal = null;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        trackpadScrollCausesScale: true,
        trackpadScrollToScaleFactor: const Offset(0.001, 0.001),
        onScaleStart: (details) {
          widget.focusNode.requestFocus();
          _scaleGestureStartScale = ref.read(workspaceProvider).scale;
        },
        onScaleUpdate: (details) {
          final pointerCount = details.pointerCount;
          final isZooming =
              pointerCount > 1 || (details.scale - 1).abs() > 0.001;
          if (!isZooming) return;

          final startScale =
              _scaleGestureStartScale ?? ref.read(workspaceProvider).scale;
          engine.zoomAt(details.localFocalPoint, startScale * details.scale);
          if (details.focalPointDelta.distanceSquared > 0) {
            engine.panBy(details.focalPointDelta);
          }
        },
        onScaleEnd: (_) {
          _scaleGestureStartScale = null;
        },
        child: Stack(
          children: [
            widget.child,
            if (_marqueeRectLocal != null)
              Positioned.fromRect(
                rect: _marqueeRectLocal!,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x334C97FF),
                      border: Border.all(
                        color: const Color(0xFF4C97FF),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNodeContextMenu(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF0F172A),
      items: const [
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
    if (!mounted || action != 'delete') return;
    await _handleDeleteWithRootConfirmation(context, ref);
  }

  Offset _toWorld(Offset local) {
    final matrix = widget.transform.value.clone()..invert();
    return MatrixUtils.transformPoint(matrix, local);
  }
}

class _NodeView extends ConsumerWidget {
  const _NodeView({
    required this.node,
    required this.highlighted,
    required this.innerHighlighted,
    required this.selected,
  });

  final BlockNode node;
  final bool highlighted;
  final bool innerHighlighted;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(workspaceProvider.notifier);
    final mode = ref.watch(sqlModeProvider);
    final runtime = ref.watch(sqlRuntimeProvider);
    final localeCode = ref.watch(localeControllerProvider).languageCode;

    String label;
    Color color;

    switch (node.type) {
      case BlockType.eventGreenFlag:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.events;
      case BlockType.sqlSelect:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.motion;
      case BlockType.sqlWhere:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.motion;
      case BlockType.sqlOrderBy:
        label = 'ORDER BY ${node.inputs['expr'] ?? 'id DESC'}';
        color = ScratchPalette.motion;
      case BlockType.sqlLoop:
        label = 'FOREVER LOOP';
        color = ScratchPalette.control;
      case BlockType.sqlJoin:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.operators;
      case BlockType.sqlGroupBy:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.operators;
      case BlockType.sqlFrom:
        label = 'FROM ${node.inputs['table'] ?? ''}'.trim();
        color = ScratchPalette.operators;
      case BlockType.sqlInsert:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.variables;
      case BlockType.sqlUpdate:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.variables;
      case BlockType.sqlDelete:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.variables;
      case BlockType.sqlCreateTable:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.operators;
      case BlockType.sqlDropTable:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.operators;
      case BlockType.sqlColumn:
        label = '${node.inputs['column'] ?? '*'}';
        color = ScratchPalette.motion;
      default:
        label = _resolvedSqlLabel(node, mode, localeCode);
        color = ScratchPalette.operators;
    }

    final height = engine.blockHeight(node);
    final measuredWidth = _computeBlockWidth(
      template: _templateForNode(node, mode, localeCode),
      values: node.inputs,
      localeCode: localeCode,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    final blockWidth = measuredWidth.clamp(
      WorkspaceController.blockWidth,
      900.0,
    );
    engine.setRenderWidth(node, blockWidth);
    final template = _templateForNode(node, mode, localeCode);
    final slotRects = _computeInlineSlots(
      template: template,
      values: node.inputs,
      maxWidth: blockWidth - 28,
      localeCode: localeCode,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    final maskedLabel = _labelMaskWithSlotSpacing(
      template: template,
      values: node.inputs,
      localeCode: localeCode,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: blockWidth,
          height: height,
          child: Stack(
            children: [
              GestureDetector(
                onDoubleTap: () => _editInput(context, node, engine),
                child: BlockShape(
                  node: node,
                  color: color,
                  width: blockWidth,
                  height: height,
                  label: maskedLabel,
                  isHighlighted: highlighted,
                  isSelected: selected,
                  showInnerHighlight: innerHighlighted,
                ),
              ),
              ...slotRects.map((slot) {
                return Positioned(
                  left: 14 + slot.rect.left,
                  top: 9,
                  child: GestureDetector(
                    onTap: () async {
                      final rb = context.findRenderObject() as RenderBox;
                      final anchor = rb.localToGlobal(
                        Offset(
                          14 + slot.rect.left + (slot.rect.width / 2),
                          9 + 20,
                        ),
                      );
                      await _editSlot(
                        context: context,
                        slotKey: slot.inputKey,
                        rawToken: slot.rawKey,
                        anchorGlobal: anchor,
                        node: node,
                        engine: engine,
                        runtime: runtime,
                        localeCode: localeCode,
                      );
                    },
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        maxWidth: 280,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Text(
                        slot.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  String _templateForNode(
    BlockNode node,
    SqlAbstractionMode mode,
    String localeCode,
  ) {
    if (node.type == BlockType.eventGreenFlag) {
      return sqlLabelFor(node.type, mode, node.inputs, localeCode);
    }
    return sqlLabelFor(node.type, mode, node.inputs, localeCode);
  }

  String _labelMaskWithSlotSpacing({
    required String template,
    required Map<String, dynamic> values,
    required String localeCode,
    required TextStyle style,
  }) {
    final pattern = RegExp(r'(\[[^\]]+\]|\{[^}]+\})');
    final buffer = StringBuffer();
    var cursor = 0;
    final spaceWidth = _measureText(' ', style);
    final safeSpaceWidth = spaceWidth <= 0 ? 4.0 : spaceWidth;

    for (final m in pattern.allMatches(template)) {
      buffer.write(template.substring(cursor, m.start));
      final token = m.group(0)!;
      final rawKey = token.substring(1, token.length - 1).trim();
      final inputKey = _slotInputKey(rawKey);
      final display = _slotDisplay(values[inputKey], rawKey, localeCode);
      final slotWidth = _slotWidthForDisplay(display, style);
      final gapWidth = _slotGap();
      var dynamicReduction = 0.0;
      var extraBeforeNextText = 0.0;
      if (inputKey == 'columns') {
        final columnItems = _selectedColumns('${values[inputKey] ?? ''}');
        final visibleColumnCount = columnItems.length.clamp(
          0,
          _maxVisibleColumnSelections,
        );
        dynamicReduction = (visibleColumnCount * 6.0).clamp(0.0, 12.0);
        // Small breathing room before trailing static text like "FROM".
        extraBeforeNextText = 8.0;
      }
      final reservedChars =
          ((slotWidth +
                      gapWidth +
                      extraBeforeNextText -
                      12.0 -
                      dynamicReduction) /
                  safeSpaceWidth)
              .ceil();
      buffer.write(' ' * reservedChars);
      cursor = m.end;
    }

    buffer.write(template.substring(cursor));
    return buffer.toString();
  }

  List<_InlineSlotRect> _computeInlineSlots({
    required String template,
    required Map<String, dynamic> values,
    required double maxWidth,
    required String localeCode,
    required TextStyle style,
  }) {
    final pattern = RegExp(r'(\[[^\]]+\]|\{[^}]+\})');
    final slots = <_InlineSlotRect>[];
    var x = 0.0;
    var cursor = 0;

    for (final m in pattern.allMatches(template)) {
      final before = template.substring(cursor, m.start);
      x += _measureText(before, style);

      final token = m.group(0)!;
      final rawKey = token.substring(1, token.length - 1).trim();
      final inputKey = _slotInputKey(rawKey);
      final display = _slotDisplay(values[inputKey], rawKey, localeCode);
      final slotWidth = _slotWidthForDisplay(display, style);
      if (x < maxWidth) {
        slots.add(
          _InlineSlotRect(
            rawKey: rawKey,
            inputKey: inputKey,
            display: display,
            rect: Rect.fromLTWH(x, 0, slotWidth, 20),
          ),
        );
      }
      x += _slotGap();
      x += slotWidth;
      cursor = m.end;
    }
    return slots;
  }

  double _computeBlockWidth({
    required String template,
    required Map<String, dynamic> values,
    required String localeCode,
    required TextStyle style,
  }) {
    final pattern = RegExp(r'(\[[^\]]+\]|\{[^}]+\})');
    var width = 14.0;
    var cursor = 0;
    for (final m in pattern.allMatches(template)) {
      width += _measureText(template.substring(cursor, m.start), style);
      final token = m.group(0)!;
      final rawKey = token.substring(1, token.length - 1).trim();
      final inputKey = _slotInputKey(rawKey);
      final display = _slotDisplay(values[inputKey], rawKey, localeCode);
      width += _slotWidthForDisplay(display, style) + _slotGap();
      cursor = m.end;
    }
    width += _measureText(template.substring(cursor), style);
    width += 14.0;
    return width;
  }

  double _slotWidthForDisplay(String display, TextStyle style) {
    return (_measureText(display, style.copyWith(fontSize: 12)) + 14).clamp(
      40.0,
      280.0,
    );
  }

  double _measureText(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: 1000);
    return painter.width;
  }

  String _slotDisplay(dynamic value, String rawKey, String localeCode) {
    final text = '${value ?? ''}'.trim();
    final rawLower = rawKey.toLowerCase();
    final normalized = text.toLowerCase();
    if (text.isEmpty) return '';
    if (normalized == rawLower) return '';
    if (normalized == 'table_name' ||
        normalized == 'column' ||
        normalized == 'column_name' ||
        normalized == 'columns') {
      return _slotDefaultDisplay(rawKey);
    }
    if (_slotInputKey(rawKey) == 'order') {
      return _localizedOrderLabel(_normalizeOrderValue(text), localeCode);
    }
    if (_slotInputKey(rawKey) == 'join_type') {
      return _localizedJoinLabel(_normalizeJoinValue(text), localeCode);
    }
    if (_slotInputKey(rawKey) == 'columns') {
      return _compactColumnSelectionDisplay(text);
    }
    return text;
  }

  String _compactColumnSelectionDisplay(String value) {
    final selected = _selectedColumns(value);
    if (selected.length <= _maxVisibleColumnSelections) return value;
    final visible = selected.take(_maxVisibleColumnSelections).join(', ');
    return '$visible, ...';
  }

  String _slotDefaultDisplay(String rawKey) {
    switch (rawKey) {
      case 'columns':
        return '*';
      case 'column':
      case 'column_name':
        return 'id';
      case 'table':
      case 'table_name':
        return '';
      case 'column_definitions':
        return 'id INTEGER PRIMARY KEY';
      case 'ASC|DESC':
      case 'aufsteigend|absteigend':
        return 'ASC';
      default:
        return '';
    }
  }

  double _slotGap() => 10.0;

  String? _inputKey(BlockNode node) {
    if (node.type == BlockType.sqlWhere) return 'predicate';
    if (node.type == BlockType.sqlOrderBy) return 'expr';
    if (node.type == BlockType.sqlGroupBy) return 'expr';
    if (node.type == BlockType.sqlFrom ||
        node.type == BlockType.sqlJoin ||
        node.type == BlockType.sqlInsert ||
        node.type == BlockType.sqlUpdate ||
        node.type == BlockType.sqlDelete ||
        node.type == BlockType.sqlCreateTable ||
        node.type == BlockType.sqlDropTable ||
        node.type == BlockType.sqlSelect) {
      return 'table';
    }
    return null;
  }

  Future<void> _editInput(
    BuildContext context,
    BlockNode node,
    WorkspaceController engine,
  ) async {
    final key = _inputKey(node);
    if (key == null) return;

    final controller = TextEditingController(text: '${node.inputs[key] ?? 10}');
    final parsed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (parsed != null) {
      engine.updateInput(node, key, parsed);
    }
  }

  Future<void> _editSlot({
    required BuildContext context,
    required String slotKey,
    required String rawToken,
    required Offset anchorGlobal,
    required BlockNode node,
    required WorkspaceController engine,
    required SqlRuntimeState runtime,
    required String localeCode,
  }) async {
    final mappedKey = _slotInputKey(slotKey);
    final options = _inlineOptionsForToken(
      rawToken: rawToken,
      mappedKey: mappedKey,
      node: node,
      runtime: runtime,
      engine: engine,
      localeCode: localeCode,
    );
    if (_isDropdownToken(rawToken, mappedKey)) {
      final picked = await _pickInlineOptionOverlay(
        context: context,
        options: options,
        anchorGlobal: anchorGlobal,
        localeCode: localeCode,
      );
      if (picked != null) {
        if (mappedKey == 'columns') {
          final current = '${node.inputs[mappedKey] ?? ''}';
          if (picked.startsWith('__REMOVE__:')) {
            final column = picked.substring('__REMOVE__:'.length);
            final reduced = _removeSelectedColumn(current, column);
            engine.updateInput(node, mappedKey, reduced);
          } else {
            final merged = _mergeSelectedColumns(current, picked);
            engine.updateInput(node, mappedKey, merged);
          }
        } else {
          engine.updateInput(node, mappedKey, picked);
        }
      }
      return;
    }

    final controller = TextEditingController(
      text: '${node.inputs[mappedKey] ?? ''}',
    );
    final parsed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (parsed != null) {
      engine.updateInput(
        node,
        mappedKey,
        _normalizeInputValue(mappedKey, parsed),
      );
    }
  }

  bool _isDropdownToken(String rawToken, String mappedKey) {
    final dropdownRaw = <String>{
      'table',
      'table_name',
      'column',
      'column_name',
      'columns',
      'JOIN_TYPE',
      'datatype',
      'ASC|DESC',
      'aufsteigend|absteigend',
      'privilege',
    };
    final dropdownMapped = <String>{
      'table',
      'column',
      'column_name',
      'columns',
      'join_type',
      'datatype',
      'order',
      'privilege',
    };
    return dropdownRaw.contains(rawToken) || dropdownMapped.contains(mappedKey);
  }

  String _resolvedSqlLabel(
    BlockNode node,
    SqlAbstractionMode mode,
    String localeCode,
  ) {
    var label = sqlLabelFor(node.type, mode, node.inputs, localeCode);
    final replacements = <String, String>{
      'table': '${node.inputs['table'] ?? ''}',
      'table_name': '${node.inputs['table'] ?? ''}',
      'columns': '${node.inputs['columns'] ?? '*'}',
      'column_definitions':
          '${node.inputs['definition'] ?? 'id INTEGER PRIMARY KEY'}',
      'column': '${node.inputs['column'] ?? node.inputs['expr'] ?? 'id'}',
      'condition': '${node.inputs['predicate'] ?? '1 = 1'}',
      'join_condition': '${node.inputs['on'] ?? '1 = 1'}',
      'JOIN_TYPE': '${node.inputs['join_type'] ?? 'INNER'}',
      'value': '${node.inputs['value'] ?? 'value'}',
      'result': '${node.inputs['result'] ?? 'result'}',
      'default': '${node.inputs['default'] ?? 'default'}',
      'column_name': '${node.inputs['column_name'] ?? 'new_column'}',
      'datatype': '${node.inputs['datatype'] ?? 'TEXT'}',
      'privilege': '${node.inputs['privilege'] ?? 'SELECT'}',
      'user': '${node.inputs['user'] ?? 'user'}',
      'name': '${node.inputs['name'] ?? 'sp1'}',
      'sql': '${node.inputs['sql'] ?? 'SELECT 1'}',
      'level': '${node.inputs['level'] ?? 'READ COMMITTED'}',
    };
    replacements.forEach((key, value) {
      label = label.replaceAll('[$key]', value);
    });
    return label;
  }

  String _slotInputKey(String slotKey) {
    switch (slotKey) {
      case 'condition':
        return 'predicate';
      case 'join_condition':
        return 'on';
      case 'table_name':
        return 'table';
      case 'column_definitions':
        return 'definition';
      case 'JOIN_TYPE':
        return 'join_type';
      case 'ASC|DESC':
      case 'aufsteigend|absteigend':
        return 'order';
      default:
        return slotKey;
    }
  }

  List<String> _inlineOptionsForToken({
    required String rawToken,
    required String mappedKey,
    required BlockNode node,
    required SqlRuntimeState runtime,
    required WorkspaceController engine,
    required String localeCode,
  }) {
    if ((mappedKey == 'table' || rawToken == 'table_name') &&
        runtime.schemas.isNotEmpty) {
      return runtime.schemas.map((s) => s.name).toList(growable: false);
    }

    if (mappedKey == 'columns' ||
        mappedKey == 'column' ||
        mappedKey == 'column_name') {
      final selectedTable =
          '${node.inputs['table'] ?? engine.contextTableForNode(node.id) ?? ''}';
      final schema = runtime.schemas.where((s) => s.name == selectedTable);
      final cols = schema.isEmpty
          ? runtime.schemas
                .expand((s) => s.columns)
                .toSet()
                .toList(growable: false)
          : schema.first.columns;
      if (mappedKey == 'columns') {
        final currentRaw = '${node.inputs['columns'] ?? '*'}';
        final selected = _selectedColumns(currentRaw);
        final options = <String>['*', ...cols];
        for (final s in selected) {
          options.add('__REMOVE__:$s');
        }
        return options;
      }
      final withDefault = <String>{'*', ...cols}.toList(growable: false);
      return withDefault;
    }

    if (mappedKey == 'join_type') {
      return const <String>[
        'INNER',
        'LEFT',
        'RIGHT',
        'FULL',
        'CROSS',
        'NATURAL',
        'SELF',
      ];
    }

    if (mappedKey == 'datatype') {
      return const <String>[
        'TEXT',
        'INTEGER',
        'REAL',
        'BLOB',
        'NUMERIC',
        'BOOLEAN',
        'DATE',
        'DATETIME',
      ];
    }

    if (mappedKey == 'order') {
      return const <String>['ASC', 'DESC'];
    }

    if (mappedKey == 'privilege') {
      return const <String>['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'ALL'];
    }

    return const <String>[];
  }

  Future<String?> _pickInlineOptionOverlay({
    required BuildContext context,
    required List<String> options,
    required Offset anchorGlobal,
    required String localeCode,
  }) async {
    final completer = Completer<String?>();
    final textController = TextEditingController();
    OverlayEntry? entry;

    void close([String? value]) {
      entry?.remove();
      if (!completer.isCompleted) completer.complete(value);
      textController.dispose();
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.4;
    entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => close(),
            ),
          ),
          Positioned(
            left: _clampOverlayLeft(context, anchorGlobal.dx, 220),
            top: _clampOverlayTop(context, anchorGlobal.dy + 8, maxHeight),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 220,
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: options.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'No schema options yet',
                                  style: TextStyle(color: Color(0xFF9CA3AF)),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (_, i) => InkWell(
                                onTap: () => close(options[i]),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Column name (or any non‑remove option)
                                        Text(
                                          _localizedOptionLabel(
                                            options[i],
                                            localeCode,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        // If this is a removal entry, show a small remove‑icon.
                                        if (options[i].startsWith(
                                          '__REMOVE__:',
                                        ))
                                          const Icon(
                                            Icons.remove_circle,
                                            size: 16,
                                            color: Colors.redAccent,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const Divider(height: 1, color: Color(0xFF334155)),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'Custom value',
                                hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: () => close(textController.text.trim()),
                            icon: const Icon(Icons.check, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(entry);
    return completer.future;
  }

  double _clampOverlayLeft(BuildContext context, double x, double width) {
    final screen = MediaQuery.of(context).size.width;
    return x.clamp(8.0, screen - width - 8.0).toDouble();
  }

  double _clampOverlayTop(BuildContext context, double y, double maxHeight) {
    final screen = MediaQuery.of(context).size.height;
    return y.clamp(8.0, screen - maxHeight - 8.0).toDouble();
  }

  String _localizedOptionLabel(String value, String localeCode) {
    // For removal entries we keep only the column name – the UI will add a remove‑icon.
    if (value.startsWith('__REMOVE__:')) {
      final col = value.substring('__REMOVE__:'.length);
      return col; // UI decides how to render the remove action.
    }
    if (value == 'ASC' || value == 'DESC') {
      return _localizedOrderLabel(value, localeCode);
    }
    const joins = <String>{
      'INNER',
      'LEFT',
      'RIGHT',
      'FULL',
      'CROSS',
      'NATURAL',
      'SELF',
    };
    if (joins.contains(value)) return _localizedJoinLabel(value, localeCode);
    return value;
  }

  String _localizedOrderLabel(String value, String localeCode) {
    final code = _normalizedLocaleCode(localeCode);
    if (value == 'ASC') {
      switch (code) {
        case 'de':
          return 'Aufsteigend';
        case 'es':
          return 'Ascendente';
        case 'fr':
          return 'Croissant';
        case 'it':
          return 'Crescente';
        case 'pt':
          return 'Ascendente';
        case 'tr':
          return 'Artan';
        case 'ja':
          return '昇順';
        case 'ko':
          return '오름차순';
        case 'zh':
          return '升序';
        case 'ar':
          return 'تصاعدي';
        default:
          return 'Ascending';
      }
    }
    switch (code) {
      case 'de':
        return 'Absteigend';
      case 'es':
        return 'Descendente';
      case 'fr':
        return 'Décroissant';
      case 'it':
        return 'Decrescente';
      case 'pt':
        return 'Descendente';
      case 'tr':
        return 'Azalan';
      case 'ja':
        return '降順';
      case 'ko':
        return '내림차순';
      case 'zh':
        return '降序';
      case 'ar':
        return 'تنازلي';
      default:
        return 'Descending';
    }
  }

  String _localizedJoinLabel(String value, String localeCode) {
    final code = _normalizedLocaleCode(localeCode);
    switch (value) {
      case 'INNER':
        return switch (code) {
          'de' => 'Inner Join (nur Treffer in beiden Tabellen)',
          'es' => 'Inner Join (coincidencias en ambas tablas)',
          'fr' => 'Inner Join (lignes présentes dans les deux tables)',
          _ => 'Inner Join (rows in both tables)',
        };
      case 'LEFT':
        return switch (code) {
          'de' => 'Left Join (alle Zeilen links + Treffer rechts)',
          'es' => 'Left Join (todas filas izquierdas + coincidencias)',
          'fr' => 'Left Join (toutes lignes gauche + correspondances)',
          _ => 'Left Join (all left rows + matches)',
        };
      case 'RIGHT':
        return switch (code) {
          'de' => 'Right Join (alle Zeilen rechts + Treffer links)',
          'es' => 'Right Join (todas filas derechas + coincidencias)',
          'fr' => 'Right Join (toutes lignes droite + correspondances)',
          _ => 'Right Join (all right rows + matches)',
        };
      case 'FULL':
        return switch (code) {
          'de' => 'Full Join (alle Zeilen aus beiden Tabellen)',
          'es' => 'Full Join (todas las filas de ambas tablas)',
          'fr' => 'Full Join (toutes les lignes des deux tables)',
          _ => 'Full Join (all rows from both tables)',
        };
      case 'CROSS':
        return switch (code) {
          'de' => 'Cross Join (jede Zeile mit jeder kombinieren)',
          'es' => 'Cross Join (combina cada fila con todas)',
          'fr' => 'Cross Join (chaque ligne combinée avec toutes)',
          _ => 'Cross Join (combine every row with every row)',
        };
      case 'NATURAL':
        return switch (code) {
          'de' => 'Natural Join (automatisch über gleiche Spaltennamen)',
          'es' => 'Natural Join (automático por columnas iguales)',
          'fr' => 'Natural Join (automatique par colonnes identiques)',
          _ => 'Natural Join (auto-join by same column names)',
        };
      case 'SELF':
        return switch (code) {
          'de' => 'Self Join (Tabelle mit sich selbst verbinden)',
          'es' => 'Self Join (unir tabla consigo misma)',
          'fr' => 'Self Join (joindre la table à elle-même)',
          _ => 'Self Join (join a table to itself)',
        };
      default:
        return value;
    }
  }

  String _normalizeOrderValue(String input) {
    final v = input.trim().toLowerCase();
    if (v.isEmpty) return 'ASC';
    if (v == 'asc' ||
        v == 'ascending' ||
        v == 'aufsteigend' ||
        v == 'ascendente' ||
        v == 'croissant' ||
        v == 'crescente' ||
        v == 'artan' ||
        v == '昇順' ||
        v == '오름차순' ||
        v == '升序' ||
        v == 'تصاعدي') {
      return 'ASC';
    }
    if (v == 'desc' ||
        v == 'descending' ||
        v == 'absteigend' ||
        v == 'descendente' ||
        v == 'décroissant' ||
        v == 'decrescente' ||
        v == 'azalan' ||
        v == '降順' ||
        v == '내림차순' ||
        v == '降序' ||
        v == 'تنازلي') {
      return 'DESC';
    }
    return input.trim().toUpperCase();
  }

  String _normalizeJoinValue(String input) {
    final normalized = input.trim().toUpperCase();
    const known = <String>{
      'INNER',
      'LEFT',
      'RIGHT',
      'FULL',
      'CROSS',
      'NATURAL',
      'SELF',
    };
    if (known.contains(normalized)) {
      return normalized;
    }
    final v = input.toLowerCase();
    if (v.contains('inner')) {
      return 'INNER';
    }
    if (v.contains('left') || v.contains('links') || v.contains('izquier')) {
      return 'LEFT';
    }
    if (v.contains('right') || v.contains('rechts') || v.contains('derech')) {
      return 'RIGHT';
    }
    if (v.contains('full') || v.contains('voll') || v.contains('complet')) {
      return 'FULL';
    }
    if (v.contains('cross') || v.contains('kreuz')) {
      return 'CROSS';
    }
    if (v.contains('natural') || v.contains('natür') || v.contains('natuer')) {
      return 'NATURAL';
    }
    if (v.contains('self') || v.contains('sich selbst') || v.contains('même')) {
      return 'SELF';
    }
    return normalized;
  }

  String _normalizeInputValue(String mappedKey, String value) {
    if (mappedKey == 'order') return _normalizeOrderValue(value);
    if (mappedKey == 'join_type') return _normalizeJoinValue(value);
    return value;
  }

  String _mergeSelectedColumns(String current, String picked) {
    final next = picked.trim();
    if (next.isEmpty) return current;
    if (next == '*') return '*';

    final existing = current
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '*')
        .toList(growable: true);

    if (!existing.any((e) => e.toLowerCase() == next.toLowerCase())) {
      existing.add(next);
    }
    return existing.isEmpty ? next : existing.join(', ');
  }

  List<String> _selectedColumns(String source) {
    return source
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '*')
        .toList(growable: false);
  }

  String _removeSelectedColumn(String current, String removeColumn) {
    final keep = _selectedColumns(current)
        .where((c) => c.toLowerCase() != removeColumn.toLowerCase())
        .toList(growable: false);
    if (keep.isEmpty) return '*';
    return keep.join(', ');
  }

  String _normalizedLocaleCode(String localeCode) {
    return localeCode.toLowerCase();
  }
}

class _InlineSlotRect {
  const _InlineSlotRect({
    required this.rawKey,
    required this.inputKey,
    required this.display,
    required this.rect,
  });

  final String rawKey;
  final String inputKey;
  final String display;
  final Rect rect;
}

class _SqlRuntimePane extends StatefulWidget {
  const _SqlRuntimePane({
    required this.sql,
    required this.runtime,
    required this.localeCode,
  });

  final String sql;
  final SqlRuntimeState runtime;
  final String localeCode;

  @override
  State<_SqlRuntimePane> createState() => _SqlRuntimePaneState();
}

class _SqlRuntimePaneState extends State<_SqlRuntimePane> {
  final ScrollController _outputHorizontal = ScrollController();
  final ScrollController _outputVertical = ScrollController();

  @override
  void dispose() {
    _outputHorizontal.dispose();
    _outputVertical.dispose();
    super.dispose();
  }

  Future<void> _copySqlToClipboard() async {
    final sql = widget.sql.trim();
    if (sql.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: sql));
    if (!mounted) return;
    final copied = widget.localeCode == 'de'
        ? 'SQL in Zwischenablage kopiert'
        : 'SQL copied to clipboard';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copied),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildSplitOutput(),
      ),
    );
  }

  Widget _buildSplitOutput() {
    return Column(
      key: const ValueKey('split'),
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Text(
                        widget.sql.isEmpty ? '-- SQL output --' : widget.sql,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFBDE0FE),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton(
                  onPressed: _copySqlToClipboard,
                  color: const Color(0xFFE2E8F0),
                  tooltip: widget.localeCode == 'de'
                      ? 'SQL kopieren'
                      : 'Copy SQL',
                  icon: const Icon(Icons.copy),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Stack(children: [Positioned.fill(child: _buildOutputBody())]),
        ),
      ],
    );
  }

  Widget _buildOutputBody() {
    if (widget.runtime.lastRows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          widget.runtime.lastMessage ?? 'No results',
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: Scrollbar(
        controller: _outputHorizontal,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _outputHorizontal,
          scrollDirection: Axis.horizontal,
          child: Scrollbar(
            controller: _outputVertical,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: _outputVertical,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: const TextStyle(color: Color(0xFFF8FAFC)),
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFF111827),
                ),
                dataRowColor: WidgetStateProperty.all(const Color(0xFF0B1220)),
                columns: widget.runtime.lastRows.first.keys
                    .map((k) => DataColumn(label: Text(k)))
                    .toList(),
                rows: widget.runtime.lastRows
                    .map(
                      (row) => DataRow(
                        cells: row.values
                            .map((v) => DataCell(Text(v)))
                            .toList(),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
