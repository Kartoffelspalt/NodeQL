import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_reporters.dart';
import 'package:nodeql/engine/block/block_syntax.dart';
import 'package:nodeql/engine/plugins/plugin_manifest.dart';
import 'package:nodeql/engine/plugins/plugin_repository.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_compiler.dart';
import 'package:nodeql/features/workbench/presentation/engine/block_snap_diagnostics.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_labels.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/features/workbench/presentation/engine/plugin_registry.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_runtime.dart';
import 'package:nodeql/features/workbench/presentation/engine/workspace_engine.dart';
import 'package:nodeql/features/workbench/presentation/scratch_style.dart';
import 'package:nodeql/features/workbench/presentation/widgets/block_shape_painter.dart';
import 'package:nodeql/features/tutorial/tutorial_controller.dart';
import 'package:nodeql/features/tutorial/tutorial_dialog.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:nodeql/localization/translation_controller.dart';
import 'package:nodeql/localization/translation_models.dart';
import 'package:nodeql/localization/translation_repository.dart';
import 'package:nodeql/localization/supported_languages.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

const int _maxVisibleColumnSelections = 3;
const double _inlineLineHeight = 28;
const double _joinFirstLineOffset = 8;
const double _joinSecondLineOffset = 18;

double _measureSingleLineText(String text, TextStyle style) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(minWidth: 0, maxWidth: 1600);
  return painter.width;
}

class _SimpleNodeDiagnostic {
  const _SimpleNodeDiagnostic({required this.title, required this.message});

  final String title;
  final String message;
}

class _SaveProjectIntent extends Intent {
  const _SaveProjectIntent();
}

Map<String, _SimpleNodeDiagnostic> _simpleNodeDiagnostics({
  required SqlAbstractionMode mode,
  required List<BlockNode> roots,
  required SqlRuntimeState runtime,
  required SqlCompileResult compileResult,
}) {
  if (mode != SqlAbstractionMode.simple) {
    return const <String, _SimpleNodeDiagnostic>{};
  }
  final diagnostics = <String, _SimpleNodeDiagnostic>{};
  for (final warning in compileResult.warnings) {
    final node = _nodeForCompilerWarning(roots, warning);
    if (node != null) {
      diagnostics[node.id] = _SimpleNodeDiagnostic(
        title: 'Problem in dieser Blockkette',
        message: _friendlyCompileWarning(warning),
      );
    }
  }
  final runtimeMessage = runtime.lastMessage;
  if (runtimeMessage == null || runtimeMessage.trim().isEmpty) {
    return diagnostics;
  }
  if (!_looksLikeRuntimeError(runtimeMessage)) return diagnostics;
  final node = _nodeForRuntimeError(roots, runtimeMessage);
  if (node == null) return diagnostics;
  diagnostics[node.id] = _SimpleNodeDiagnostic(
    title: 'Fehler an diesem Node',
    message: _friendlyRuntimeError(runtimeMessage),
  );
  return diagnostics;
}

bool _looksLikeRuntimeError(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('error') ||
      normalized.contains('exception') ||
      normalized.contains('no such table') ||
      normalized.contains('no such column') ||
      normalized.contains('no database connected') ||
      normalized.contains('database file not found') ||
      normalized.contains('syntax error') ||
      normalized.startsWith('rolled back:') ||
      normalized.startsWith('failed ');
}

BlockNode? _nodeForCompilerWarning(List<BlockNode> roots, String warning) {
  final idMatch = RegExp(r'"([^"]+)"').firstMatch(warning);
  final id = idMatch?.group(1);
  if (id == null) return null;
  return _findNodeById(roots, id);
}

String _friendlyCompileWarning(String warning) {
  if (warning.contains('not executable')) {
    return 'Dieser Block ist nicht mit ABFRAGE AUSFÜHREN verbunden.';
  }
  if (warning.contains('Cycle detected')) {
    return 'Diese Blockkette bildet eine Schleife. Trenne einen der verbundenen Blöcke.';
  }
  if (warning.contains('Plugin block')) {
    return 'Dieser Plugin-Block ist nicht verfügbar oder passt nicht mehr zur installierten Version.';
  }
  if (warning.contains('failed:')) {
    return 'Dieser Zusatz-Block konnte nicht übersetzt werden. Prüfe seine Eingaben oder installiere das Plugin neu.';
  }
  if (warning.contains('created with version')) {
    return 'Dieser Plugin-Block wurde mit einer anderen Version erstellt. Prüfe, ob das Plugin aktualisiert wurde.';
  }
  return 'Dieser Block konnte noch nicht verständlich geprüft werden. Prüfe seine Verbindung und die eingetragenen Werte.';
}

String _visibleCompileWarnings({
  required SqlAbstractionMode mode,
  required List<String> warnings,
}) {
  if (mode != SqlAbstractionMode.simple) return warnings.join('\n');
  return warnings.map(_friendlyCompileWarning).join('\n');
}

BlockNode? _nodeForRuntimeError(List<BlockNode> roots, String message) {
  final normalized = message.toLowerCase();
  final noSuchTable = RegExp(
    r'no such table: ([^\s,)]+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (noSuchTable != null) {
    final table = _stripSqlToken(noSuchTable.group(1)!);
    return _firstNodeWhere(
      roots,
      (node) =>
          node.inputs['table']?.toString() == table ||
          node.inputs['table_name']?.toString() == table,
    );
  }
  final noSuchColumn = RegExp(
    r'no such column: ([^\s,)]+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (noSuchColumn != null) {
    final column = _stripSqlToken(noSuchColumn.group(1)!);
    return _firstNodeWhere(
      roots,
      (node) => node.inputs.values.any((value) {
        final text = value?.toString() ?? '';
        return text == column ||
            text.endsWith('.$column') ||
            text.split(',').map((part) => part.trim()).contains(column);
      }),
    );
  }
  final near = RegExp(
    r'near "([^"]+)": syntax error',
    caseSensitive: false,
  ).firstMatch(message);
  if (near != null) {
    final token = near.group(1)!.toUpperCase();
    final node = _firstNodeWhere(
      roots,
      (node) => _sqlKeywordForNode(node.type) == token,
    );
    if (node != null) return node;
  }
  if (normalized.contains('syntax error')) {
    return _firstNodeWhere(roots, _likelySyntaxProblemNode);
  }
  if (normalized.contains('constraint')) {
    return _firstNodeWhere(
      roots,
      (node) =>
          node.type == BlockType.sqlInsert ||
          node.type == BlockType.sqlUpdate ||
          node.type == BlockType.sqlDelete,
    );
  }
  return _firstNodeWhere(
    roots,
    (node) => node.type != BlockType.eventGreenFlag,
  );
}

String _friendlyRuntimeError(String message) {
  final normalized = message.toLowerCase();
  final noSuchTable = RegExp(
    r'no such table: ([^\s,)]+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (noSuchTable != null) {
    return 'Diese Tabelle wurde in der geladenen Datenbank nicht gefunden. Prüfe den Tabellen-Slot.';
  }
  final noSuchColumn = RegExp(
    r'no such column: ([^\s,)]+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (noSuchColumn != null) {
    return 'Diese Spalte wurde nicht gefunden. Prüfe Spaltenauswahl, Join-Spalten oder Filter-Spalte.';
  }
  if (normalized.contains('ambiguous column')) {
    return 'Diese Spalte gibt es in mehreren Tabellen. Wähle eindeutig, aus welcher Tabelle die Spalte kommt.';
  }
  if (normalized.contains('misuse of aggregate')) {
    return 'Eine Rechenfunktion wie SUM oder COUNT steht an der falschen Stelle. Nutze sie meist in SELECT oder HAVING.';
  }
  if (normalized.contains('incomplete input')) {
    return 'Die Abfrage ist unvollständig. Prüfe, ob ein Pflichtfeld leer ist oder ein Block fehlt.';
  }
  if (normalized.contains('syntax error') || normalized.contains('near "')) {
    return 'Die SQL-Struktur ist an dieser Stelle ungültig. Prüfe die Reihenfolge und die Slots dieses Nodes.';
  }
  if (normalized.contains('unique constraint')) {
    return 'Dieser Wert darf in der Tabelle nur einmal vorkommen. Wähle einen anderen Wert.';
  }
  if (normalized.contains('foreign key constraint')) {
    return 'Dieser Wert verweist auf einen fehlenden Eintrag in einer anderen Tabelle.';
  }
  if (normalized.contains('not null constraint')) {
    return 'Ein Pflichtfeld ist leer. Trage für diese Spalte einen Wert ein.';
  }
  if (normalized.contains('constraint')) {
    return 'Die Datenbank lehnt diese Änderung wegen einer Regel ab. Prüfe Werte und Schlüssel.';
  }
  if (normalized.contains('datatype mismatch')) {
    return 'Der Wert passt nicht zum Spaltentyp. Prüfe, ob du Zahl, Text oder Datum richtig eingetragen hast.';
  }
  if (normalized.contains('readonly') || normalized.contains('read-only')) {
    return 'Die Datenbank kann gerade nicht beschrieben werden. Prüfe Datei- und Ordnerrechte.';
  }
  if (normalized.contains('database is locked')) {
    return 'Die Datenbank ist gerade durch einen anderen Zugriff gesperrt. Schließe andere Programme oder versuche es erneut.';
  }
  if (normalized.contains('no database connected')) {
    return 'Es ist keine Datenbank verbunden. Wähle zuerst eine .db-Datei aus.';
  }
  if (normalized.contains('database file not found')) {
    return 'Die Datenbankdatei wurde nicht gefunden. Wähle die Datei erneut aus.';
  }
  if (normalized.contains('failed to open database')) {
    return 'Die Datenbank konnte nicht geöffnet werden. Prüfe, ob es wirklich eine SQLite-.db-Datei ist.';
  }
  return 'Prüfe diesen Node und seine Slots. Die technische Meldung steht rechts im SQL-Ausgabebereich.';
}

String _friendlyVisibleRuntimeMessage({
  required SqlAbstractionMode mode,
  required String message,
}) {
  if (mode != SqlAbstractionMode.simple || !_looksLikeRuntimeError(message)) {
    return message;
  }
  return _friendlyRuntimeError(message);
}

_SimpleNodeDiagnostic _dragRejectedDiagnostic(SqlAbstractionMode mode) {
  if (mode == SqlAbstractionMode.simple) {
    return const _SimpleNodeDiagnostic(
      title: 'Block passt hier nicht',
      message:
          'Ziehe den Block an eine passende Stelle in der Reihenfolge: Anzeigen, Tabelle, Verbinden, Filtern, Gruppieren, Sortieren.',
    );
  }
  return const _SimpleNodeDiagnostic(
    title: 'Ungültige Verbindung',
    message: 'Dieser Block kann an dieser Stelle nicht verbunden werden.',
  );
}

String _stripSqlToken(String token) {
  return token
      .replaceAll('"', '')
      .replaceAll('`', '')
      .replaceAll('[', '')
      .replaceAll(']', '')
      .split('.')
      .last
      .trim();
}

bool _likelySyntaxProblemNode(BlockNode node) {
  return switch (node.type) {
    BlockType.sqlWhere ||
    BlockType.sqlJoin ||
    BlockType.sqlInnerJoin ||
    BlockType.sqlLeftJoin ||
    BlockType.sqlRightJoin ||
    BlockType.sqlFullJoin ||
    BlockType.sqlHaving ||
    BlockType.sqlOrderBy ||
    BlockType.sqlInsert ||
    BlockType.sqlUpdate ||
    BlockType.sqlDelete => true,
    _ => false,
  };
}

String? _sqlKeywordForNode(BlockType type) {
  return switch (type) {
    BlockType.sqlSelect => 'SELECT',
    BlockType.sqlFrom => 'FROM',
    BlockType.sqlWhere => 'WHERE',
    BlockType.sqlJoin ||
    BlockType.sqlInnerJoin ||
    BlockType.sqlLeftJoin ||
    BlockType.sqlRightJoin ||
    BlockType.sqlFullJoin ||
    BlockType.sqlCrossJoin ||
    BlockType.sqlNaturalJoin ||
    BlockType.sqlSelfJoin => 'JOIN',
    BlockType.sqlGroupBy => 'GROUP',
    BlockType.sqlHaving => 'HAVING',
    BlockType.sqlOrderBy => 'ORDER',
    BlockType.sqlInsert => 'INSERT',
    BlockType.sqlUpdate => 'UPDATE',
    BlockType.sqlDelete => 'DELETE',
    BlockType.sqlCreateTable => 'CREATE',
    BlockType.sqlAlterTable => 'ALTER',
    BlockType.sqlDropTable => 'DROP',
    _ => null,
  };
}

BlockNode? _findNodeById(List<BlockNode> roots, String id) {
  return _firstNodeWhere(roots, (node) => node.id == id);
}

BlockNode? _firstNodeWhere(
  Iterable<BlockNode> roots,
  bool Function(BlockNode node) predicate,
) {
  for (final root in roots) {
    final found = _firstNodeInTree(root, predicate, <String>{});
    if (found != null) return found;
  }
  return null;
}

BlockNode? _firstNodeInTree(
  BlockNode node,
  bool Function(BlockNode node) predicate,
  Set<String> seen,
) {
  if (!seen.add(node.id)) return null;
  if (predicate(node)) return node;
  for (final child in node.children) {
    final found = _firstNodeInTree(child, predicate, seen);
    if (found != null) return found;
  }
  final next = node.next;
  return next == null ? null : _firstNodeInTree(next, predicate, seen);
}

Color _sqlColorForType(BlockType type) {
  if (type == BlockType.eventGreenFlag) return ScratchPalette.events;
  if (isJoinType(type)) return ScratchPalette.sqlJoin;
  return switch (blockVisualKindForType(type)) {
    BlockVisualKind.statement when type == BlockType.sqlSelect =>
      ScratchPalette.sqlQuery,
    BlockVisualKind.statement
        when type == BlockType.sqlInsert ||
            type == BlockType.sqlUpdate ||
            type == BlockType.sqlDelete =>
      ScratchPalette.sqlMutation,
    BlockVisualKind.statement
        when type == BlockType.sqlCreateTable ||
            type == BlockType.sqlAlterTable ||
            type == BlockType.sqlTruncate ||
            type == BlockType.sqlDropTable ||
            type == BlockType.sqlGrant ||
            type == BlockType.sqlRevoke =>
      ScratchPalette.sqlSchema,
    BlockVisualKind.statement => ScratchPalette.sqlTransaction,
    BlockVisualKind.setOperator => ScratchPalette.sqlSet,
    BlockVisualKind.join => ScratchPalette.sqlJoin,
    BlockVisualKind.expression => ScratchPalette.sqlExpression,
    BlockVisualKind.terminal => ScratchPalette.sqlTransaction,
    BlockVisualKind.container => ScratchPalette.control,
    BlockVisualKind.clause when type == BlockType.sqlFrom =>
      ScratchPalette.sqlSource,
    BlockVisualKind.clause
        when type == BlockType.sqlWhere || type == BlockType.sqlOrderBy =>
      ScratchPalette.sqlFilter,
    BlockVisualKind.clause => ScratchPalette.sqlAggregate,
    BlockVisualKind.trigger => ScratchPalette.events,
    BlockVisualKind.pluginStatement ||
    BlockVisualKind.pluginValue ||
    BlockVisualKind.pluginContainer => ScratchPalette.myBlocks,
  };
}

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
  bool _autosaveEnabledForProject = true;
  List<Map<String, dynamic>> _recentProjects = <Map<String, dynamic>>[];
  int _lastAutosaveRevision = -1;
  Timer? _autosaveDebounce;
  double _paletteWidth = 250;
  bool _tutorialWasPresented = false;
  bool _blockDiagnosticsRunning = false;
  int _blockDiagnosticsRunToken = 0;
  ProviderSubscription<TutorialState>? _tutorialSubscription;

  @override
  void initState() {
    super.initState();
    _menuChannel.setMethodCallHandler(_handleNativeMenuAction);
    Future<void>.microtask(
      () => ref.read(pluginPaletteProvider.notifier).reload(),
    );
    _restoreAutosave();
    _tutorialSubscription = ref.listenManual<TutorialState>(
      tutorialControllerProvider,
      (_, next) {
        if (!next.loading && !next.completed && !_tutorialWasPresented) {
          _tutorialWasPresented = true;
          Future<void>.delayed(const Duration(milliseconds: 450), () {
            if (mounted) _openTutorial(context);
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _menuChannel.setMethodCallHandler(null);
    _autosaveDebounce?.cancel();
    _tutorialSubscription?.close();
    _workspaceFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final translationState = ref.watch(translationControllerProvider);
    final catalog = translationState.catalog;
    final locale = translationState.locale;
    final workspaceRevision = ref.watch(
      workspaceProvider.select((s) => s.revision),
    );
    final workspaceRoots = ref.read(workspaceProvider).roots;
    final runtime = ref.watch(sqlRuntimeProvider);
    final mode = ref.watch(sqlModeProvider);
    final pluginState = ref.watch(pluginPaletteProvider);
    final compileResult = _compiler.compileWorkspace(
      workspaceRoots,
      pluginBlocks: pluginState.blocksByQualifiedId,
    );
    final sql = compileResult.sql;
    final nodeDiagnostics = _simpleNodeDiagnostics(
      mode: mode,
      roots: workspaceRoots,
      runtime: runtime,
      compileResult: compileResult,
    );
    _maybeAutosave(workspaceRevision);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _SaveProjectIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveProjectIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveProjectIntent: CallbackAction<_SaveProjectIntent>(
            onInvoke: (_) {
              unawaited(_saveProject(context));
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  catalog: catalog,
                  languageChoices: <SupportedLanguage>[
                    ...supportedLanguages,
                    for (final package in translationState.installed.values)
                      if (!supportedLanguages.any(
                        (language) => language.code == package.locale,
                      ))
                        SupportedLanguage(package.locale, package.locale),
                  ],
                  localeCode: locale.languageCode,
                  onLocale: (code) => ref
                      .read(translationControllerProvider.notifier)
                      .setLocaleTag(code),
                  onPickDb: () =>
                      ref.read(sqlRuntimeProvider.notifier).pickDatabase(),
                  onExecuteGuarded: () {
                    if (compileResult.sql.trim().isEmpty) {
                      ref
                          .read(sqlRuntimeProvider.notifier)
                          .setMessage(
                            compileResult.warnings.isEmpty
                                ? catalog.text('runtime.noExecutable')
                                : _visibleCompileWarnings(
                                    mode: mode,
                                    warnings: compileResult.warnings,
                                  ),
                          );
                      return;
                    }
                    ref
                        .read(sqlRuntimeProvider.notifier)
                        .executeWithSnapshot(sql);
                    if (compileResult.warnings.isNotEmpty) {
                      ref
                          .read(sqlRuntimeProvider.notifier)
                          .setMessage(
                            catalog.text('runtime.executedWithWarnings', {
                              'warnings': _visibleCompileWarnings(
                                mode: mode,
                                warnings: compileResult.warnings,
                              ),
                            }),
                          );
                    }
                  },
                  mode: mode,
                  onModeChanged: (next) =>
                      ref.read(sqlModeProvider.notifier).setMode(next),
                  onSettings: () => _openSettings(context),
                  onTutorial: () => _openTutorial(context),
                  onDiagnostics: () => _openBlockDiagnostics(context),
                ),
                Expanded(
                  child: Row(
                    children: [
                      _CategoryRail(
                        active: _activeCategory,
                        hasPlugins: pluginState.entries.isNotEmpty,
                        onSelect: (next) =>
                            setState(() => _activeCategory = next),
                      ),
                      _Palette(
                        category: _activeCategory,
                        runtime: runtime,
                        mode: mode,
                        localeCode: locale.languageCode,
                        catalog: catalog,
                        width: _paletteWidth,
                        pluginEntries: pluginState.entries,
                        onAdd: (type, defaults) {
                          final controller = ref.read(
                            workspaceProvider.notifier,
                          );
                          controller.addTemplate(
                            type,
                            controller.suggestedTemplatePosition(type),
                            defaults: defaults,
                          );
                        },
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
                              color: NodeQlWorkbenchColors.of(context).border,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _WorkspaceCanvas(
                          focusNode: _workspaceFocus,
                          transform: _transform,
                          paletteWidth: 72.0 + _paletteWidth,
                          diagnostics: nodeDiagnostics,
                          onSaveProject: () => _saveProject(context),
                        ),
                      ),
                      _SqlRuntimePane(
                        sql: sql,
                        runtime: runtime,
                        mode: mode,
                        localeCode: locale.languageCode,
                        catalog: catalog,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _maybeAutosave(int revision) async {
    if (!_autosaveEnabledForProject) {
      _autosaveDebounce?.cancel();
      return;
    }
    if (revision == _lastAutosaveRevision) return;
    _lastAutosaveRevision = revision;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 550), () async {
      final support = await getApplicationSupportDirectory();
      final autosave = File(
        '${support.path}/nodeql_autosave_$_activeProjectId.nodeql',
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
              await _loadProjectPayload(
                source,
                projectPath: _activeProjectPath,
              );
              return;
            }
          }
        } catch (_) {}
      }
    }
    final support = await getApplicationSupportDirectory();
    final autosave = File(
      '${support.path}/nodeql_autosave_$_activeProjectId.nodeql',
    );
    final legacySqpAutosave = File(
      '${support.path}/nodeql_autosave_$_activeProjectId.sqp',
    );
    final legacyScratchQlAutosave = File(
      '${support.path}/scratchql_autosave_$_activeProjectId.scratchql',
    );
    final legacyScratchQlSqpAutosave = File(
      '${support.path}/scratchql_autosave_$_activeProjectId.sqp',
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
    final catalog = ref.read(translationControllerProvider).catalog;
    final createDb = ValueNotifier<bool>(true);
    final autosaveProject = ValueNotifier<bool>(true);
    final projectName = TextEditingController(text: 'NodeQL Project');
    final dbName = TextEditingController(text: 'nodeql_project');
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(catalog.text('project.new.title')),
        content: ValueListenableBuilder<bool>(
          valueListenable: createDb,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(catalog.text('project.new.reset')),
              const SizedBox(height: 10),
              TextField(
                controller: projectName,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: catalog.text('project.new.projectName'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: value,
                    onChanged: (v) => createDb.value = v ?? false,
                  ),
                  Expanded(
                    child: Text(catalog.text('project.new.createDatabase')),
                  ),
                ],
              ),
              ValueListenableBuilder<bool>(
                valueListenable: autosaveProject,
                builder: (context, autosaveEnabled, _) => Row(
                  children: [
                    Checkbox(
                      value: autosaveEnabled,
                      onChanged: (v) => autosaveProject.value = v ?? true,
                    ),
                    Expanded(child: Text(catalog.text('project.new.autosave'))),
                  ],
                ),
              ),
              if (value)
                TextField(
                  controller: dbName,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: catalog.text('project.new.databaseName'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(catalog.text('common.no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(catalog.text('common.yes')),
          ),
        ],
      ),
    );
    if (yes == true) {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: catalog.text('project.new.directoryDialog'),
      );
      if (selectedDirectory == null) {
        dbName.dispose();
        projectName.dispose();
        createDb.dispose();
        return;
      }
      final projectDirectory = Directory(selectedDirectory);
      await projectDirectory.create(recursive: true);
      final rawProjectName = projectName.text.trim().isEmpty
          ? catalog.text('project.untitled')
          : projectName.text.trim();
      final projectPath = await _availableProjectPath(
        projectDirectory,
        rawProjectName,
      );
      ref.read(workspaceProvider.notifier).resetWithRoot();
      if (createDb.value) {
        try {
          await ref
              .read(sqlRuntimeProvider.notifier)
              .createEmptyDatabase(
                preferredName: dbName.text,
                directoryPath: projectDirectory.path,
              );
        } catch (e) {
          ref
              .read(sqlRuntimeProvider.notifier)
              .setMessage(
                catalog.text('project.createDatabaseFailed', {'error': e}),
              );
        }
      }
      setState(() {
        _activeProjectPath = projectPath;
        _activeProjectId = 'project_${DateTime.now().millisecondsSinceEpoch}';
        _activeProjectName = rawProjectName;
        _autosaveEnabledForProject = autosaveProject.value;
        _upsertRecentProject();
      });
      await File(
        projectPath,
      ).writeAsString(jsonEncode(_projectEnvelope()), flush: true);
      await _saveProjectRegistry();
      await _syncRecentProjectsToNativeMenu();
    }
    dbName.dispose();
    projectName.dispose();
    createDb.dispose();
    autosaveProject.dispose();
  }

  Future<void> _saveProjectAs(BuildContext context) async {
    final catalog = ref.read(translationControllerProvider).catalog;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: catalog.text('project.saveDialog'),
      fileName: 'project.nodeql',
      type: FileType.custom,
      allowedExtensions: <String>['nodeql'],
    );
    if (path == null) return;
    setState(() {
      _activeProjectPath = path;
      _activeProjectId = 'project_${DateTime.now().millisecondsSinceEpoch}';
      _activeProjectName = _projectNameFromPath(path);
      _upsertRecentProject();
    });
    await File(path).writeAsString(jsonEncode(_projectEnvelope()), flush: true);
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
    final catalog = ref.read(translationControllerProvider).catalog;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: catalog.text('project.openDialog'),
      type: FileType.custom,
      allowedExtensions: <String>['nodeql', 'scratchql', 'sqlq', 'sqp'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final source = await File(path).readAsString();
    await _loadProjectPayload(source, projectPath: path);
    setState(() {
      _activeProjectPath = path;
      final existing = _recentProjects.where((p) => p['path'] == path).toList();
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
    final catalog = ref.read(translationControllerProvider).catalog;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(catalog.text('settings.title')),
        content: Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(nodeQlThemeProvider);
            return RadioGroup<NodeQlTheme>(
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  ref.read(nodeQlThemeProvider.notifier).setTheme(value);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<NodeQlTheme>(
                    value: NodeQlTheme.light,
                    title: Text(catalog.text('settings.theme.light')),
                  ),
                  RadioListTile<NodeQlTheme>(
                    value: NodeQlTheme.dark,
                    title: Text(catalog.text('settings.theme.dark')),
                  ),
                  RadioListTile<NodeQlTheme>(
                    value: NodeQlTheme.midnight,
                    title: Text(catalog.text('settings.theme.midnight')),
                  ),
                  RadioListTile<NodeQlTheme>(
                    value: NodeQlTheme.matrix,
                    title: Text(catalog.text('settings.theme.matrix')),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => _openPluginManager(context),
                    child: Text(catalog.text('settings.plugins')),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => _openLanguageManager(context),
                    child: Text(catalog.text('settings.languages')),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openTutorial(this.context);
                    },
                    icon: const Icon(Icons.school_outlined),
                    label: Text(catalog.text('settings.tutorial')),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _openAbout(context),
                    icon: const Icon(Icons.info_outline),
                    label: Text(catalog.text('settings.about')),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openBlockDiagnostics(BuildContext context) async {
    final report = buildBlockSnapDiagnosticReport();
    final allowedCases = report.allowedCases;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block-Tests'),
        content: SizedBox(
          width: 680,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Geprüft: ${report.total} Kombinationen, '
                '${report.allowed} erlaubt, ${report.blocked} blockiert.',
              ),
              const SizedBox(height: 8),
              const Text('Erlaubte Snap-Konstellationen'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: allowedCases.length,
                  itemBuilder: (context, index) {
                    final entry = allowedCases[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(
                        '${_diagnosticLabel(entry.previous)} -> '
                        '${_diagnosticLabel(entry.next)}',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: _blockDiagnosticsRunning
                ? null
                : () {
                    Navigator.of(context).pop();
                    _runVisibleBlockDiagnostics(allowedCases);
                  },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Live-Test starten'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  String _diagnosticLabel(BlockType type) {
    return sqlLabelFor(
      type,
      SqlAbstractionMode.advanced,
      const <String, dynamic>{},
      'de',
    ).replaceAll('\n', ' ');
  }

  Future<void> _runVisibleBlockDiagnostics(
    List<BlockSnapDiagnosticCase> cases,
  ) async {
    if (_blockDiagnosticsRunning || cases.isEmpty) return;
    final controller = ref.read(workspaceProvider.notifier);
    final originalWorkspace = controller.toJsonString();
    final token = ++_blockDiagnosticsRunToken;

    setState(() => _blockDiagnosticsRunning = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Live-Block-Test gestartet (${cases.length} Fälle)'),
        duration: const Duration(milliseconds: 1500),
      ),
    );

    try {
      for (var index = 0; index < cases.length; index++) {
        if (!mounted ||
            token != _blockDiagnosticsRunToken ||
            !_blockDiagnosticsRunning) {
          break;
        }
        await _playSnapDiagnosticCase(cases[index]);
      }
    } finally {
      if (mounted && token == _blockDiagnosticsRunToken) {
        controller.restorePreviewSnapshot(originalWorkspace);
        setState(() => _blockDiagnosticsRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live-Block-Test abgeschlossen'),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }

  Future<void> _playSnapDiagnosticCase(BlockSnapDiagnosticCase testCase) async {
    final controller = ref.read(workspaceProvider.notifier);
    controller.resetWithRoot(recordUndo: false);
    final target = testCase.previous == BlockType.eventGreenFlag
        ? ref.read(workspaceProvider).roots.single
        : controller.addTemplate(
            testCase.previous,
            const Offset(260, 180),
            autoSnap: false,
            recordUndo: false,
          );
    final dragged = controller.addTemplate(
      testCase.next,
      const Offset(600, 180),
      autoSnap: false,
      recordUndo: false,
    );

    await Future<void>.delayed(const Duration(milliseconds: 90));
    controller.startDrag(
      dragged.position + const Offset(10, 10),
      recordUndo: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final destination = Offset(
      target.position.dx,
      target.position.dy + controller.blockHeight(target),
    );
    final totalDelta = destination - dragged.position;
    const steps = 12;
    final stepDelta = totalDelta / steps.toDouble();
    for (var step = 0; step < steps; step++) {
      controller.updateDrag(stepDelta);
      await Future<void>.delayed(const Duration(milliseconds: 18));
    }
    controller.endDrag(recordUndo: false);
    await Future<void>.delayed(const Duration(milliseconds: 90));
  }

  Future<void> _openTutorial(BuildContext context) async {
    if (!mounted) return;
    final catalog = ref.read(translationControllerProvider).catalog;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TutorialDialog(
        catalog: catalog,
        onComplete: () =>
            ref.read(tutorialControllerProvider.notifier).complete(),
      ),
    );
  }

  Future<void> _openAbout(BuildContext context) async {
    final package = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: 'NodeQL',
      applicationVersion: '${package.version}+${package.buildNumber}',
      applicationLegalese: 'Copyright © 2026 NodeQL contributors\nMIT License',
      applicationIcon: const Icon(Icons.account_tree_outlined, size: 48),
    );
  }

  Future<void> _openPluginManager(BuildContext context) async {
    final catalog = ref.read(translationControllerProvider).catalog;
    await ref.read(pluginPaletteProvider.notifier).reload();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          title: Text(catalog.text('plugins.title')),
          content: SizedBox(
            width: 720,
            height: 500,
            child: Consumer(
              builder: (context, ref, _) {
                final plugins = ref.watch(pluginPaletteProvider);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: catalog.text('plugins.installedTab')),
                        Tab(text: catalog.text('plugins.repositoriesTab')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _InstalledPluginsView(
                            plugins: plugins,
                            catalog: catalog,
                            onUninstall: (id) => ref
                                .read(pluginPaletteProvider.notifier)
                                .uninstall(id),
                          ),
                          _PluginRepositoriesView(
                            plugins: plugins,
                            catalog: catalog,
                            onAdd: () => _addPluginRepository(dialogContext),
                            onRefresh: () => ref
                                .read(pluginPaletteProvider.notifier)
                                .refreshRepositories(),
                            onRemove: (url) => ref
                                .read(pluginPaletteProvider.notifier)
                                .removeRepository(url),
                            onInstall: (entry) =>
                                _installRepositoryPlugin(dialogContext, entry),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () =>
                  ref.read(pluginPaletteProvider.notifier).reload(),
              icon: const Icon(Icons.refresh),
              label: Text(catalog.text('plugins.reload')),
            ),
            FilledButton.icon(
              onPressed: () => _installPluginManifest(dialogContext),
              icon: const Icon(Icons.add),
              label: Text(catalog.text('plugins.install')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(catalog.text('common.close')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPluginRepository(BuildContext context) async {
    final catalog = ref.read(translationControllerProvider).catalog;
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(catalog.text('plugins.repository.add')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: catalog.text('plugins.repository.url'),
            hintText: 'https://example.org/nodeql/catalog.json',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(catalog.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(catalog.text('plugins.repository.add')),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      await ref.read(pluginPaletteProvider.notifier).addRepository(url);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            catalog.text('plugins.repository.failed', {'error': error}),
          ),
        ),
      );
    }
  }

  Future<void> _installRepositoryPlugin(
    BuildContext context,
    PluginRepositoryEntry entry,
  ) async {
    final catalog = ref.read(translationControllerProvider).catalog;
    try {
      await ref
          .read(pluginPaletteProvider.notifier)
          .installRepositoryPlugin(entry);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            catalog.text('plugins.installed', {
              'name': entry.name,
              'version': entry.version,
            }),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            catalog.text('plugins.installFailed', {'error': error}),
          ),
        ),
      );
    }
  }

  Future<void> _openLanguageManager(BuildContext context) async {
    final controller = ref.read(translationControllerProvider.notifier);
    await controller.refreshManifest();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final translations = ref.watch(translationControllerProvider);
          final catalog = translations.catalog;
          final available = translations.available;
          return AlertDialog(
            title: Text(catalog.text('languages.title')),
            content: SizedBox(
              width: 620,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (translations.error != null)
                    MaterialBanner(
                      content: Text(
                        defaultTranslationManifestUrl.isEmpty
                            ? catalog.text('languages.notConfigured')
                            : translations.error!,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => controller.refreshManifest(),
                          child: Text(catalog.text('languages.refresh')),
                        ),
                      ],
                    ),
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: translations.locale.languageCode,
                      onChanged: (value) {
                        if (value != null) controller.setLocaleTag(value);
                      },
                      child: ListView(
                        children: [
                          for (final language in supportedLanguages)
                            ListTile(
                              onTap: () =>
                                  controller.setLocaleTag(language.code),
                              leading: const Icon(Icons.translate),
                              title: Text(language.nativeName),
                              subtitle: Text(catalog.text('languages.builtIn')),
                              trailing: Radio<String>(value: language.code),
                            ),
                          for (final language in available)
                            if (!supportedLanguages.any(
                              (builtIn) => builtIn.code == language.locale,
                            ))
                              _LanguagePackTile(
                                language: language,
                                installed:
                                    translations.installed[language.locale],
                                active:
                                    translations.catalog.locale ==
                                    language.locale,
                                catalog: catalog,
                                onInstall: () => controller.install(language),
                                onRemove: () =>
                                    controller.remove(language.locale),
                                onSelect: () =>
                                    controller.setLocaleTag(language.locale),
                              ),
                        ],
                      ),
                    ),
                  ),
                  if (translations.syncing) const LinearProgressIndicator(),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: controller.openContributionGuide,
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: Text(catalog.text('languages.contribute')),
              ),
              TextButton.icon(
                onPressed: controller.refreshManifest,
                icon: const Icon(Icons.refresh),
                label: Text(catalog.text('languages.refresh')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(catalog.text('common.close')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _installPluginManifest(BuildContext context) async {
    final catalog = ref.read(translationControllerProvider).catalog;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: catalog.text('plugins.selectDialog'),
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final manifest = await ref
          .read(pluginPaletteProvider.notifier)
          .installManifest(File(path));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            catalog.text('plugins.installed', {
              'name': manifest.name,
              'version': manifest.version,
            }),
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            catalog.text('plugins.installFailed', {'error': error}),
          ),
        ),
      );
    }
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

  Map<String, dynamic> _projectEnvelope() {
    final workspace =
        jsonDecode(ref.read(workspaceProvider.notifier).toJsonString())
            as Map<String, dynamic>;
    final runtime = ref.read(sqlRuntimeProvider);
    final mode = ref.read(sqlModeProvider);
    final locale = ref.read(translationControllerProvider).locale;
    final theme = ref.read(nodeQlThemeProvider);
    final dbPath = runtime.dbPath;
    final projectPath = _activeProjectPath;
    final dbRelativePath = dbPath != null && projectPath != null
        ? _relativePathIfInsideProject(dbPath, projectPath)
        : null;
    final runtimePayload = <String, dynamic>{'dbPath': dbPath};
    if (dbRelativePath != null) {
      runtimePayload['dbRelativePath'] = dbRelativePath;
    }
    return <String, dynamic>{
      'format': 'nodeql_project_v2',
      'version': 2,
      'workspace': workspace,
      'runtime': runtimePayload,
      'ui': <String, dynamic>{
        'mode': mode.name,
        'locale': locale.languageCode,
        'theme': theme.name,
      },
      'settings': <String, dynamic>{
        'autosaveEnabled': _autosaveEnabledForProject,
      },
    };
  }

  String? _relativePathIfInsideProject(String dbPath, String projectPath) {
    final projectDir = p.dirname(projectPath);
    if (!p.isWithin(projectDir, dbPath) && p.normalize(dbPath) != projectDir) {
      return null;
    }
    return p.relative(dbPath, from: projectDir);
  }

  Future<void> _loadProjectPayload(String source, {String? projectPath}) async {
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {}

    if (decoded == null || !_isProjectEnvelopeFormat(decoded['format'])) {
      _autosaveEnabledForProject = true;
      ref.read(workspaceProvider.notifier).loadFromJsonString(source);
      return;
    }

    final settings = decoded['settings'] as Map<String, dynamic>? ?? {};
    _autosaveEnabledForProject = settings['autosaveEnabled'] as bool? ?? true;

    final workspace =
        (decoded['workspace'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    ref
        .read(workspaceProvider.notifier)
        .loadFromJsonString(jsonEncode(workspace));

    final runtime = decoded['runtime'] as Map<String, dynamic>? ?? {};
    final dbPath = _resolveProjectDbPath(
      runtime['dbPath'] as String?,
      runtime['dbRelativePath'] as String?,
      projectPath,
    );
    if (dbPath != null && dbPath.trim().isNotEmpty) {
      await ref.read(sqlRuntimeProvider.notifier).attachDatabasePath(dbPath);
    }
  }

  String? _resolveProjectDbPath(
    String? dbPath,
    String? dbRelativePath,
    String? projectPath,
  ) {
    if (projectPath != null &&
        dbRelativePath != null &&
        dbRelativePath.trim().isNotEmpty) {
      return p.normalize(p.join(p.dirname(projectPath), dbRelativePath));
    }
    return dbPath;
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

  Future<String> _availableProjectPath(Directory directory, String name) async {
    final baseName = _projectFileStem(name);
    var candidate = p.join(directory.path, '$baseName.nodeql');
    var suffix = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(directory.path, '$baseName-$suffix.nodeql');
      suffix += 1;
    }
    return candidate;
  }

  String _projectFileStem(String name) {
    final sanitized = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    final withoutExtension = sanitized.toLowerCase().endsWith('.nodeql')
        ? sanitized.substring(0, sanitized.length - '.nodeql'.length)
        : sanitized;
    final cleaned = withoutExtension.trim();
    return cleaned.isEmpty ? 'project' : cleaned;
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
    await _loadProjectPayload(source, projectPath: path);
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
    required this.catalog,
    required this.languageChoices,
    required this.localeCode,
    required this.onLocale,
    required this.onPickDb,
    required this.onExecuteGuarded,
    required this.mode,
    required this.onModeChanged,
    required this.onSettings,
    required this.onTutorial,
    required this.onDiagnostics,
  });

  final TranslationCatalog catalog;
  final List<SupportedLanguage> languageChoices;
  final String localeCode;
  final ValueChanged<String> onLocale;
  final VoidCallback onPickDb;
  final VoidCallback onExecuteGuarded;
  final SqlAbstractionMode mode;
  final ValueChanged<SqlAbstractionMode> onModeChanged;
  final VoidCallback onSettings;
  final VoidCallback onTutorial;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: workbenchColors.topBar,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    catalog.text('app.name'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: workbenchColors.topBarForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: onPickDb,
                    style: TextButton.styleFrom(
                      foregroundColor: workbenchColors.topBarForeground,
                    ),
                    child: Text(catalog.text('toolbar.mountDatabase')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onExecuteGuarded,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(catalog.text('toolbar.runSql')),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<SqlAbstractionMode>(
                    segments: [
                      ButtonSegment(
                        value: SqlAbstractionMode.simple,
                        label: Text(catalog.text('toolbar.simple')),
                      ),
                      ButtonSegment(
                        value: SqlAbstractionMode.advanced,
                        label: Text(catalog.text('toolbar.advanced')),
                      ),
                    ],
                    selected: <SqlAbstractionMode>{mode},
                    onSelectionChanged: (selection) =>
                        onModeChanged(selection.first),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: localeCode,
                    dropdownColor: workbenchColors.panelElevated,
                    items: languageChoices
                        .map(
                          (l) => DropdownMenuItem(
                            value: l.code,
                            child: Text(
                              l.nativeName,
                              style: TextStyle(
                                color: workbenchColors.topBarForeground,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onLocale(v);
                    },
                  ),
                  IconButton(
                    key: const ValueKey('open-tutorial'),
                    onPressed: onTutorial,
                    tooltip: catalog.text('toolbar.tutorial'),
                    color: workbenchColors.topBarForeground,
                    icon: const Icon(Icons.school_outlined),
                  ),
                  IconButton(
                    onPressed: onSettings,
                    tooltip: catalog.text('toolbar.settings'),
                    color: workbenchColors.topBarForeground,
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

class _LanguagePackTile extends StatelessWidget {
  const _LanguagePackTile({
    required this.language,
    required this.installed,
    required this.active,
    required this.catalog,
    required this.onInstall,
    required this.onRemove,
    required this.onSelect,
  });

  final TranslationLanguage language;
  final TranslationPackage? installed;
  final bool active;
  final TranslationCatalog catalog;
  final VoidCallback onInstall;
  final VoidCallback onRemove;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final hasUpdate =
        installed != null && installed!.revision < language.revision;
    return ListTile(
      leading: Icon(
        language.direction == TranslationDirection.rtl
            ? Icons.format_textdirection_r_to_l
            : Icons.translate,
      ),
      title: Text(language.nativeName),
      subtitle: Text(
        installed == null
            ? catalog.text('languages.available', {
                'completion': language.completion,
              })
            : catalog.text('languages.installed', {
                'revision': installed!.revision,
              }),
      ),
      onTap: installed == null ? null : onSelect,
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (active) const Icon(Icons.check_circle, color: Colors.green),
          if (installed == null || hasUpdate)
            TextButton(
              onPressed: onInstall,
              child: Text(
                catalog.text(
                  hasUpdate ? 'languages.update' : 'languages.install',
                ),
              ),
            ),
          if (installed != null)
            IconButton(
              onPressed: onRemove,
              tooltip: catalog.text('languages.remove'),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

class _InstalledPluginsView extends StatelessWidget {
  const _InstalledPluginsView({
    required this.plugins,
    required this.catalog,
    required this.onUninstall,
  });

  final PluginPaletteState plugins;
  final TranslationCatalog catalog;
  final ValueChanged<String> onUninstall;

  @override
  Widget build(BuildContext context) {
    if (plugins.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        Text(
          plugins.pluginsDirectory ?? catalog.text('plugins.loadingDirectory'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (plugins.manifests.isEmpty)
          ListTile(
            leading: const Icon(Icons.extension_off),
            title: Text(catalog.text('plugins.none')),
            subtitle: Text(catalog.text('plugins.noneHint')),
          ),
        for (final manifest in plugins.manifests)
          ListTile(
            leading: Icon(
              manifest.schemaVersion >= 2
                  ? Icons.hub_outlined
                  : Icons.extension,
            ),
            title: Text(manifest.name),
            subtitle: Text(
              '${manifest.id}  •  ${manifest.version}  •  SDK v${manifest.schemaVersion}\n'
              '${catalog.text('plugins.blocks', {'count': manifest.blocks.length})}'
              '${manifest.dataSources.isEmpty ? '' : '  •  ${catalog.text('plugins.dataSources', {'count': manifest.dataSources.length})}'}'
              '${manifest.networkHosts.isEmpty ? '' : '\n${catalog.text('plugins.networkHosts')}: ${manifest.networkHosts.join(', ')}'}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: catalog.text('plugins.uninstall'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onUninstall(manifest.id),
            ),
          ),
        for (final issue in plugins.issues)
          ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: Text(issue.message),
            subtitle: Text(issue.path),
          ),
      ],
    );
  }
}

class _PluginRepositoriesView extends StatelessWidget {
  const _PluginRepositoriesView({
    required this.plugins,
    required this.catalog,
    required this.onAdd,
    required this.onRefresh,
    required this.onRemove,
    required this.onInstall,
  });

  final PluginPaletteState plugins;
  final TranslationCatalog catalog;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;
  final ValueChanged<Uri> onRemove;
  final ValueChanged<PluginRepositoryEntry> onInstall;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                catalog.text('plugins.repository.hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              tooltip: catalog.text('plugins.repository.refresh'),
              icon: const Icon(Icons.sync),
            ),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_link),
              label: Text(catalog.text('plugins.repository.add')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: plugins.repositories.isEmpty
              ? Center(child: Text(catalog.text('plugins.repository.none')))
              : ListView(
                  children: [
                    for (final source in plugins.repositories) ...[
                      ListTile(
                        leading: const Icon(Icons.cloud_outlined),
                        title: Text(
                          plugins.repositoryCatalogs[source.url]?.name ??
                              source.url.host,
                        ),
                        subtitle: Text(source.url.toString()),
                        trailing: IconButton(
                          onPressed: () => onRemove(source.url),
                          tooltip: catalog.text('plugins.repository.remove'),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                      if (plugins.repositoryErrors[source.url]
                          case final error?)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                          ),
                          title: Text(error),
                        ),
                      for (final entry
                          in plugins.repositoryCatalogs[source.url]?.entries ??
                              const <PluginRepositoryEntry>[])
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.extension_outlined),
                            title: Text(entry.name),
                            subtitle: Text(
                              '${entry.id}  •  ${entry.version}\n${entry.description}',
                            ),
                            isThreeLine: true,
                            trailing: FilledButton(
                              onPressed: () => onInstall(entry),
                              child: Text(catalog.text('plugins.install')),
                            ),
                          ),
                        ),
                      const Divider(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

enum SqlPaletteCategory { dql, dml, ddl, dcl, txn, plugins }

class _PaletteItem {
  const _PaletteItem({
    required this.key,
    required this.type,
    required this.label,
    required this.description,
    required this.color,
    this.defaults,
  });

  final String key;
  final BlockType type;
  final String label;
  final String description;
  final Color color;
  final Map<String, dynamic>? defaults;
}

class _PaletteDragData {
  const _PaletteDragData(this.type, this.defaults);

  final BlockType type;
  final Map<String, dynamic>? defaults;
}

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
    required this.catalog,
    required this.width,
    required this.pluginEntries,
    required this.onAdd,
  });

  final SqlPaletteCategory category;
  final SqlRuntimeState runtime;
  final SqlAbstractionMode mode;
  final String localeCode;
  final TranslationCatalog catalog;
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
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    final tileWidth = (widget.width - 32).clamp(160.0, 500.0);
    final query = _query.trim().toLowerCase();
    final sourceBlocks = query.isEmpty
        ? _blocksForCategory(widget.category)
        : _allSearchableBlocks();
    final blocks = query.isEmpty
        ? sourceBlocks
        : sourceBlocks
              .where((block) {
                return block.label.toLowerCase().contains(query) ||
                    block.description.toLowerCase().contains(query) ||
                    block.key.toLowerCase().contains(query);
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(
                  Icons.search,
                  color: workbenchColors.muted,
                  size: 20,
                ),
                hintText: widget.catalog.text('palette.search'),
                hintStyle: TextStyle(color: workbenchColors.muted),
                filled: true,
                fillColor: workbenchColors.panelElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: workbenchColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: workbenchColors.border),
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
                Expanded(
                  child: Text(
                    query.isEmpty
                        ? _categoryTitle(widget.category, widget.localeCode)
                        : widget.catalog.text('palette.searchResults'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${blocks.length}',
                  style: TextStyle(color: workbenchColors.muted, fontSize: 11),
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
                        type: block.type,
                        label: block.label,
                        description: block.description,
                        color: block.color,
                        node: _templateNode(block.type, block.defaults),
                        width: tileWidth,
                        onAdd: () => widget.onAdd(block.type, block.defaults),
                        onHelp: () => _showCommandHelp(
                          context,
                          block.label,
                          block.description,
                        ),
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

  List<_PaletteItem> _blocksForCategory(SqlPaletteCategory category) {
    String lbl(BlockType type) =>
        sqlLabelFor(type, widget.mode, const {}, widget.localeCode);
    _PaletteItem native(BlockType type) => _PaletteItem(
      key: type.name,
      type: type,
      label: lbl(type),
      description: _commandHelp(type, widget.localeCode),
      color: _colorForType(type),
    );
    return switch (category) {
      SqlPaletteCategory.dql => <_PaletteItem>[
        native(BlockType.eventGreenFlag),
        native(BlockType.sqlSelect),
        native(BlockType.sqlColumn),
        native(BlockType.sqlText),
        native(BlockType.sqlWhere),
        native(BlockType.sqlJoin),
        native(BlockType.sqlGroupBy),
        native(BlockType.sqlHaving),
        native(BlockType.sqlOrderBy),
        native(BlockType.sqlSubqueryIn),
        native(BlockType.sqlSubqueryAny),
        native(BlockType.sqlSubqueryAll),
        native(BlockType.sqlCount),
        native(BlockType.sqlSum),
        native(BlockType.sqlAvg),
        native(BlockType.sqlMin),
        native(BlockType.sqlMax),
        native(BlockType.sqlConcat),
        native(BlockType.sqlSubstring),
        native(BlockType.sqlLength),
        native(BlockType.sqlUpper),
        native(BlockType.sqlLower),
        native(BlockType.sqlTrim),
        native(BlockType.sqlLeft),
        native(BlockType.sqlRight),
        native(BlockType.sqlReplace),
        native(BlockType.sqlCurrentDate),
        native(BlockType.sqlCurrentTime),
        native(BlockType.sqlCurrentTimestamp),
        native(BlockType.sqlDatePart),
        native(BlockType.sqlDateAdd),
        native(BlockType.sqlDateSub),
        native(BlockType.sqlExtract),
        native(BlockType.sqlToChar),
        native(BlockType.sqlTimestampDiff),
        native(BlockType.sqlDateDiff),
        native(BlockType.sqlCase),
        native(BlockType.sqlIf),
        native(BlockType.sqlCoalesce),
        native(BlockType.sqlNullIf),
        native(BlockType.sqlFrom),
      ],
      SqlPaletteCategory.dml => <_PaletteItem>[
        native(BlockType.sqlInsert),
        native(BlockType.sqlUpdate),
        native(BlockType.sqlDelete),
      ],
      SqlPaletteCategory.ddl => <_PaletteItem>[
        native(BlockType.sqlCreateTable),
        native(BlockType.sqlAlterTable),
        native(BlockType.sqlTruncate),
        native(BlockType.sqlDropTable),
        native(BlockType.sqlGrant),
        native(BlockType.sqlRevoke),
      ],
      SqlPaletteCategory.dcl => <_PaletteItem>[
        native(BlockType.sqlGrant),
        native(BlockType.sqlRevoke),
      ],
      SqlPaletteCategory.txn => <_PaletteItem>[
        native(BlockType.sqlCommit),
        native(BlockType.sqlRollback),
        native(BlockType.sqlSavepoint),
        native(BlockType.sqlRollbackToSavepoint),
        native(BlockType.sqlSetTransaction),
        native(BlockType.sqlUnion),
        native(BlockType.sqlIntersect),
        native(BlockType.sqlExcept),
      ],
      SqlPaletteCategory.plugins =>
        widget.pluginEntries
            .map(
              (entry) => _PaletteItem(
                key: entry.block.qualifiedId,
                type: entry.blockType,
                label: entry.block.uiTemplateFor(widget.localeCode),
                description: entry.descriptionFor(widget.localeCode),
                color: Color(entry.block.colorValue),
                defaults: entry.defaults,
              ),
            )
            .toList(growable: false),
    };
  }

  List<_PaletteItem> _allSearchableBlocks() {
    final seen = <String>{};
    final all = <_PaletteItem>[];
    for (final category in SqlPaletteCategory.values) {
      if (category == SqlPaletteCategory.plugins &&
          widget.pluginEntries.isEmpty) {
        continue;
      }
      for (final block in _blocksForCategory(category)) {
        if (seen.add(block.key)) all.add(block);
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
      case BlockType.sqlText:
        return de
            ? 'Erzeugt einen Textwert, der in runde Eingabefelder eingesetzt werden kann.'
            : 'Creates a text value that can be inserted into rounded input slots.';
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

  Future<void> _showCommandHelp(
    BuildContext context,
    String label,
    String description,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(description),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.catalog.text('common.ok')),
          ),
        ],
      ),
    );
  }

  String _categoryTitle(SqlPaletteCategory category, String localeCode) {
    return switch (category) {
      SqlPaletteCategory.dql => widget.catalog.text('palette.category.dql'),
      SqlPaletteCategory.dml => widget.catalog.text('palette.category.dml'),
      SqlPaletteCategory.ddl => widget.catalog.text('palette.category.ddl'),
      SqlPaletteCategory.dcl => widget.catalog.text('palette.category.dcl'),
      SqlPaletteCategory.txn => widget.catalog.text('palette.category.txn'),
      SqlPaletteCategory.plugins => widget.catalog.text(
        'palette.category.plugins',
      ),
    };
  }

  BlockNode _templateNode(BlockType type, Map<String, dynamic>? defaults) {
    final node = switch (type) {
      BlockType.sqlSelect =>
        OperatorBlock(id: 'tpl_sel', position: Offset.zero, operatorType: type)
          ..inputs.addAll(<String, dynamic>{
            'columns': '*',
            'table': 'table_name',
            'separate_from': false,
          }),
      BlockType.eventGreenFlag => EventBlock(
        id: 'tpl_evt',
        position: Offset.zero,
      ),
      BlockType.sqlColumn => OperatorBlock(
        id: 'tpl_column',
        position: Offset.zero,
        operatorType: type,
        inputs: <String, dynamic>{'column': '*'},
      ),
      BlockType.sqlText => OperatorBlock(
        id: 'tpl_text',
        position: Offset.zero,
        operatorType: type,
        inputs: <String, dynamic>{'text': 'Text'},
      ),
      BlockType.sqlCount => OperatorBlock(
        id: 'tpl_count',
        position: Offset.zero,
        operatorType: type,
        inputs: <String, dynamic>{'expr': '*'},
      ),
      BlockType.sqlSum ||
      BlockType.sqlAvg ||
      BlockType.sqlMin ||
      BlockType.sqlMax => OperatorBlock(
        id: 'tpl_aggregate',
        position: Offset.zero,
        operatorType: type,
        inputs: <String, dynamic>{'expr': 'amount'},
      ),
      BlockType.sqlWhere || BlockType.sqlOrderBy => MotionBlock(
        id: 'tpl_mot',
        position: Offset.zero,
        motionType: type,
      ),
      BlockType.sqlLoop => ControlBlock(
        id: 'tpl_ctl',
        position: Offset.zero,
        controlType: type,
      ),
      _ => OperatorBlock(
        id: 'tpl_op',
        position: Offset.zero,
        operatorType: type,
      ),
    };
    if (defaults != null) node.inputs.addAll(defaults);
    return node;
  }

  Color _colorForType(BlockType type) {
    return _sqlColorForType(type);
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
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    final blockHeight = baseHeightForBlock(node);
    final previewWidth = _palettePreviewWidth(label, width);
    final block = BlockShape(
      node: node,
      color: color,
      width: previewWidth,
      height: blockHeight,
      label: label,
    );

    return Draggable<_PaletteDragData>(
      data: _PaletteDragData(type, node.inputs),
      feedback: Material(color: Colors.transparent, child: block),
      child: GestureDetector(
        onTap: onAdd,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: workbenchColors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: workbenchColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: width,
                    height: blockHeight,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: block,
                    ),
                  ),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  double _palettePreviewWidth(String label, double cardWidth) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    final maxLineWidth = label
        .split('\n')
        .map((line) => _measureSingleLineText(line, style))
        .fold<double>(0, math.max);
    final contentPadding = blockVisualKindForType(type) == BlockVisualKind.join
        ? 72.0
        : 58.0;
    return math
        .max(cardWidth, maxLineWidth + contentPadding)
        .clamp(cardWidth, cardWidth * 1.35);
  }
}

class _WorkspaceCanvas extends ConsumerWidget {
  const _WorkspaceCanvas({
    required this.focusNode,
    required this.transform,
    required this.paletteWidth,
    required this.diagnostics,
    required this.onSaveProject,
  });

  final FocusNode focusNode;
  final TransformationController transform;
  final double paletteWidth;
  final Map<String, _SimpleNodeDiagnostic> diagnostics;
  final Future<void> Function() onSaveProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final controller = ref.read(workspaceProvider.notifier);
    transform.value = Matrix4.identity()
      ..translateByDouble(workspace.pan.dx, workspace.pan.dy, 0, 1)
      ..scaleByDouble(workspace.scale, workspace.scale, workspace.scale, 1);

    return DragTarget<_PaletteDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final rb = context.findRenderObject() as RenderBox;
        final local = rb.globalToLocal(details.offset);
        controller.addTemplate(
          details.data.type,
          _toWorld(local),
          defaults: details.data.defaults,
        );
      },
      builder: (context, _, _) => Focus(
        autofocus: true,
        focusNode: focusNode,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final keyboard = HardwareKeyboard.instance;
          final cmdOrCtrl = keyboard.isMetaPressed || keyboard.isControlPressed;
          if (cmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
            unawaited(onSaveProject());
            return KeyEventResult.handled;
          }
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
            color: NodeQlWorkbenchColors.of(context).workspace,
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
                          child: RepaintBoundary(
                            child: _NodeView(
                              node: block,
                              diagnostic: diagnostics[block.id],
                              highlighted:
                                  workspace.highlightTargetId == block.id,
                              rejected: workspace.rejectedTargetId == block.id,
                              innerHighlighted:
                                  workspace.highlightTargetId == block.id &&
                                  (workspace.highlightZone ==
                                          SnapZone.innerTop ||
                                      workspace.highlightZone ==
                                          SnapZone.innerBottom),
                              selected: workspace.selectedBlockIds.contains(
                                block.id,
                              ),
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
  final catalog = ref.read(translationControllerProvider).catalog;
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
      title: Text(catalog.text('workspace.deleteRoot.title')),
      content: Text(catalog.text('workspace.deleteRoot.message')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(catalog.text('common.no')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(catalog.text('common.yes')),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    ref.read(workspaceProvider.notifier).deleteSelected();
  }
}

double _lineOffsetForNode(BlockVisualKind visualKind, double lineTop) {
  if (visualKind != BlockVisualKind.join) return 0;
  return lineTop >= _inlineLineHeight
      ? _joinSecondLineOffset
      : _joinFirstLineOffset;
}

double _inlineCenterOffsetForNode({
  required BlockVisualKind visualKind,
  required double height,
  required _InlineNodeLayout layout,
}) {
  if (visualKind == BlockVisualKind.join) return 0;
  if (layout.textRuns.isEmpty && layout.slots.isEmpty) return 0;

  var minTop = double.infinity;
  var maxBottom = 0.0;
  for (final run in layout.textRuns) {
    minTop = math.min(minTop, run.offset.dy);
    maxBottom = math.max(maxBottom, run.offset.dy + 20);
  }
  for (final slot in layout.slots) {
    minTop = math.min(minTop, slot.rect.top);
    maxBottom = math.max(maxBottom, slot.rect.bottom);
  }
  if (!minTop.isFinite) return 0;

  final contentHeight = maxBottom - minTop;
  final centeredTop = (height - contentHeight) / 2;
  return centeredTop - 9 - minTop;
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
    final catalog = ref.read(translationControllerProvider).catalog;
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
      color: NodeQlWorkbenchColors.of(context).panelElevated,
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(catalog.text('workspace.delete')),
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
    required this.diagnostic,
    required this.highlighted,
    required this.rejected,
    required this.innerHighlighted,
    required this.selected,
  });

  final BlockNode node;
  final _SimpleNodeDiagnostic? diagnostic;
  final bool highlighted;
  final bool rejected;
  final bool innerHighlighted;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(workspaceProvider.notifier);
    final mode = ref.watch(sqlModeProvider);
    final runtime = ref.watch(sqlRuntimeProvider);
    final localeCode = ref
        .watch(translationControllerProvider)
        .locale
        .languageCode;
    final pluginBlock = pluginBlockForNode(
      node,
      ref.watch(pluginPaletteProvider),
    );
    final color = pluginBlock == null
        ? _colorForNodeType(node.type)
        : Color(pluginBlock.colorValue);

    final pluginShape = pluginBlock?.shape.name;
    final visualKind = blockVisualKind(node, pluginShape: pluginShape);
    final template = _templateForNode(node, mode, localeCode, pluginBlock);
    final effectiveDiagnostic =
        diagnostic ?? (rejected ? _dragRejectedDiagnostic(mode) : null);
    final measuredWidth =
        _computeBlockWidth(
          node: node,
          template: template,
          values: node.inputs,
          mode: mode,
          localeCode: localeCode,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ) +
        (visualKind == BlockVisualKind.trigger ? 34 : 0);
    final blockWidth = measuredWidth.clamp(
      WorkspaceController.blockWidth,
      1100.0,
    );
    final contentLeft = switch (visualKind) {
      BlockVisualKind.trigger => 49.0,
      BlockVisualKind.join => 26.0,
      BlockVisualKind.pluginStatement ||
      BlockVisualKind.pluginValue ||
      BlockVisualKind.pluginContainer => 28.0,
      _ => 14.0,
    };
    final inlineLayout = _computeInlineLayout(
      node: node,
      template: template,
      values: node.inputs,
      maxWidth: blockWidth - contentLeft - 12,
      mode: mode,
      localeCode: localeCode,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    final usesInlineOverlay = inlineLayout.slots.isNotEmpty;
    final maskedLabel = _labelMaskWithSlotSpacing(
      node: node,
      template: template,
      values: node.inputs,
      mode: mode,
      localeCode: localeCode,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    final computedHeight = _heightForNodeContent(
      baseHeight: engine.blockHeight(node),
      template: template,
      slotRects: inlineLayout.slots,
      textRuns: inlineLayout.textRuns,
      isJoin: visualKind == BlockVisualKind.join,
    );
    final inlineCenterOffset = _inlineCenterOffsetForNode(
      visualKind: visualKind,
      height: computedHeight,
      layout: inlineLayout,
    );
    engine.setRenderMetrics(node, width: blockWidth, height: computedHeight);

    final blockContent = Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: blockWidth,
          height: computedHeight,
          child: Stack(
            children: [
              GestureDetector(
                onDoubleTap: () => _editInput(context, node, engine),
                child: BlockShape(
                  node: node,
                  color: color,
                  width: blockWidth,
                  height: computedHeight,
                  label: usesInlineOverlay ? '' : maskedLabel,
                  pluginShape: pluginShape,
                  isHighlighted: highlighted,
                  isErrorHighlighted: effectiveDiagnostic != null,
                  isSelected: selected,
                  showInnerHighlight: innerHighlighted,
                  showLabel: !usesInlineOverlay,
                ),
              ),
              if (usesInlineOverlay)
                ...inlineLayout.textRuns.map(
                  (run) => Positioned(
                    left: contentLeft + run.offset.dx,
                    top:
                        9 +
                        inlineCenterOffset +
                        run.offset.dy +
                        _lineOffsetForNode(visualKind, run.offset.dy),
                    child: Text(
                      run.text,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ...inlineLayout.slots.map((slot) {
                final acceptsReporter = slotAcceptsReporter(
                  slot.rawKey,
                  slot.inputKey,
                );
                return Positioned(
                  left: contentLeft + slot.rect.left,
                  top:
                      9 +
                      inlineCenterOffset +
                      slot.rect.top +
                      _lineOffsetForNode(visualKind, slot.rect.top),
                  child: DragTarget<_PaletteDragData>(
                    onWillAcceptWithDetails: (details) =>
                        acceptsReporter &&
                        slotAcceptsReporterType(
                          slot.rawKey,
                          slot.inputKey,
                          details.data.type,
                        ),
                    onAcceptWithDetails: (details) {
                      final reporter = slot.reporter;
                      final nestedKey = reporter == null
                          ? null
                          : primaryReporterInputKey(reporter.type);
                      if (slot.inputKey == 'aggregate') {
                        engine.setReporterInput(
                          node,
                          slot.inputKey,
                          details.data.type,
                          defaults: details.data.defaults,
                        );
                      } else if (reporter != null && nestedKey != null) {
                        engine.setNestedReporterInput(
                          node,
                          slot.inputKey,
                          reporter,
                          nestedKey,
                          details.data.type,
                          defaults: details.data.defaults,
                        );
                      } else {
                        engine.setReporterInput(
                          node,
                          slot.inputKey,
                          details.data.type,
                          defaults: details.data.defaults,
                        );
                      }
                    },
                    builder: (context, candidates, _) {
                      final highlighted = candidates.isNotEmpty;
                      return GestureDetector(
                        onTap: () async {
                          if (slot.reporter != null) {
                            await _editReporterSlot(
                              context: context,
                              node: node,
                              slot: slot,
                              engine: engine,
                              runtime: runtime,
                              localeCode: localeCode,
                            );
                            return;
                          }
                          final rb = context.findRenderObject() as RenderBox;
                          final anchor = rb.localToGlobal(
                            Offset(slot.rect.width / 2, slot.rect.height),
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
                        onLongPress: slot.reporter == null
                            ? null
                            : () => engine.removeReporterInput(
                                node,
                                slot.inputKey,
                              ),
                        child: slot.reporter == null
                            ? Container(
                                width: slot.rect.width,
                                height: slot.rect.height,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: highlighted
                                      ? const Color(0xFF38BDF8)
                                      : Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: highlighted
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.55),
                                    width: highlighted ? 2 : 1,
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
                              )
                            : AnimatedScale(
                                scale: highlighted ? 1.05 : 1,
                                duration: const Duration(milliseconds: 100),
                                child: BlockShape(
                                  node: slot.reporter!,
                                  color: _colorForNodeType(slot.reporter!.type),
                                  width: slot.rect.width,
                                  height: slot.rect.height,
                                  label: _reporterLabelForSlot(
                                    slot.reporter!,
                                    localeCode,
                                    mode,
                                    slot.inputKey,
                                  ),
                                  isHighlighted: highlighted,
                                ),
                              ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        if (effectiveDiagnostic != null)
          Positioned(
            left: blockWidth + 10,
            top: 4,
            width: 280,
            child: _NodeDiagnosticBadge(diagnostic: effectiveDiagnostic),
          ),
      ],
    );

    final animatedBlockContent = AnimatedScale(
      scale: highlighted || rejected || selected ? 1.012 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      child: blockContent,
    );

    if (node.type == BlockType.sqlHaving) {
      return DragTarget<_PaletteDragData>(
        onWillAcceptWithDetails: (details) => slotAcceptsReporterType(
          'aggregate',
          'aggregate',
          details.data.type,
        ),
        onAcceptWithDetails: (details) {
          engine.setReporterInput(
            node,
            'aggregate',
            details.data.type,
            defaults: details.data.defaults,
          );
        },
        builder: (context, candidates, _) => AnimatedScale(
          scale: candidates.isEmpty ? 1 : 1.02,
          duration: const Duration(milliseconds: 100),
          child: animatedBlockContent,
        ),
      );
    }

    return animatedBlockContent;
  }

  String _templateForNode(
    BlockNode node,
    SqlAbstractionMode mode,
    String localeCode,
    NodeQlPluginBlock? pluginBlock,
  ) {
    if (pluginBlock != null) return pluginBlock.uiTemplateFor(localeCode);
    return sqlLabelFor(node.type, mode, node.inputs, localeCode);
  }

  String _reporterLabel(
    BlockNode reporter,
    String localeCode,
    SqlAbstractionMode mode,
  ) {
    if (reporter.type == BlockType.sqlColumn) {
      final column = '${reporter.inputs['column'] ?? '*'}';
      if (mode == SqlAbstractionMode.simple && column.trim() == '*') {
        return simpleAllColumnsLabel(localeCode);
      }
      return column;
    }
    if (reporter.type == BlockType.sqlText) {
      return '"${reporter.inputs['text'] ?? ''}"';
    }
    final nested = reporterForInput(reporter, 'expr');
    final value = nested == null
        ? '${reporter.inputs['expr'] ?? reporter.inputs['column'] ?? '*'}'
        : _reporterLabel(nested, localeCode, mode);
    return switch (reporter.type) {
      BlockType.sqlCount => 'COUNT($value)',
      BlockType.sqlSum => 'SUM($value)',
      BlockType.sqlAvg => 'AVG($value)',
      BlockType.sqlMin => 'MIN($value)',
      BlockType.sqlMax => 'MAX($value)',
      BlockType.sqlLength => 'LENGTH($value)',
      BlockType.sqlUpper => 'UPPER($value)',
      BlockType.sqlLower => 'LOWER($value)',
      BlockType.sqlTrim => 'TRIM($value)',
      _ => sqlLabelFor(
        reporter.type,
        SqlAbstractionMode.advanced,
        reporter.inputs,
        localeCode,
      ),
    };
  }

  String _reporterLabelForSlot(
    BlockNode reporter,
    String localeCode,
    SqlAbstractionMode mode,
    String? inputKey,
  ) {
    if (inputKey == 'aggregate') {
      return switch (reporter.type) {
        BlockType.sqlCount => 'COUNT',
        BlockType.sqlSum => 'SUM',
        BlockType.sqlAvg => 'AVG',
        BlockType.sqlMin => 'MIN',
        BlockType.sqlMax => 'MAX',
        _ => _reporterLabel(reporter, localeCode, mode),
      };
    }
    return _reporterLabel(reporter, localeCode, mode);
  }

  Future<void> _editReporterSlot({
    required BuildContext context,
    required BlockNode node,
    required _InlineSlotRect slot,
    required WorkspaceController engine,
    required SqlRuntimeState runtime,
    required String localeCode,
  }) async {
    final reporter = slot.reporter;
    if (reporter == null) return;
    final catalog = translationCatalogOf(context);
    final nestedKey = primaryReporterInputKey(reporter.type);
    final nestedReporter = nestedKey == null
        ? null
        : reporterForInput(reporter, nestedKey);

    if (reporter.type == BlockType.sqlColumn ||
        nestedReporter?.type == BlockType.sqlColumn) {
      final columnReporter = nestedReporter ?? reporter;
      final allowMultiple = nestedReporter == null;
      final selectedTable =
          '${node.inputs['table'] ?? engine.contextTableForNode(node.id) ?? ''}';
      final selectedSchema = runtime.schemas.where(
        (schema) => schema.name == selectedTable,
      );
      final columns = selectedSchema.isEmpty
          ? runtime.schemas
                .expand((schema) => schema.columns)
                .toSet()
                .toList(growable: false)
          : selectedSchema.first.columns;
      final selectedColumns = '${columnReporter.inputs['column'] ?? '*'}'
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && value != '*')
          .toSet();
      var selectAll = '${columnReporter.inputs['column'] ?? '*'}'.trim() == '*';
      final result = await showDialog<_ColumnReporterEditResult>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              catalog.text('editor.chooseColumn', {'table': selectedTable}),
            ),
            content: SizedBox(
              width: 360,
              height: 320,
              child: columns.isEmpty
                  ? Center(child: Text(catalog.text('editor.noSchemaOptions')))
                  : ListView(
                      children: [
                        CheckboxListTile(
                          value: selectAll,
                          secondary: const Icon(Icons.select_all),
                          title: Text(simpleAllColumnsLabel(localeCode)),
                          onChanged: (selected) {
                            setDialogState(() {
                              selectAll = selected == true;
                              if (selectAll) selectedColumns.clear();
                            });
                          },
                        ),
                        const Divider(height: 1),
                        for (final column in columns)
                          CheckboxListTile(
                            value: selectedColumns.contains(column),
                            secondary: const Icon(Icons.view_column_outlined),
                            title: Text(column),
                            onChanged: selectAll
                                ? null
                                : (selected) {
                                    setDialogState(() {
                                      if (!allowMultiple) {
                                        selectedColumns.clear();
                                      }
                                      if (selected == true) {
                                        selectAll = false;
                                        selectedColumns.add(column);
                                      } else {
                                        selectedColumns.remove(column);
                                      }
                                    });
                                  },
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _ColumnReporterEditResult(removeReporter: true)),
                icon: const Icon(Icons.remove_circle_outline),
                label: Text(catalog.text('editor.removeReporter')),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(catalog.text('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _ColumnReporterEditResult(
                    value: selectAll || selectedColumns.isEmpty
                        ? '*'
                        : selectedColumns.join(', '),
                  ),
                ),
                child: Text(catalog.text('common.ok')),
              ),
            ],
          ),
        ),
      );
      if (result?.removeReporter == true) {
        if (nestedReporter != null && nestedKey != null) {
          engine.removeNestedReporterInput(
            node,
            slot.inputKey,
            reporter,
            nestedKey,
          );
        } else {
          engine.removeReporterInput(node, slot.inputKey);
        }
        return;
      }
      final picked = result?.value;
      if (picked != null) {
        if (nestedReporter != null && nestedKey != null) {
          engine.updateNestedReporterInput(
            node,
            slot.inputKey,
            reporter,
            nestedKey,
            nestedReporter,
            'column',
            picked,
          );
        } else {
          engine.updateReporterInput(
            node,
            slot.inputKey,
            columnReporter,
            'column',
            picked,
          );
        }
      }
      return;
    }

    if (reporter.type == BlockType.sqlText ||
        nestedReporter?.type == BlockType.sqlText) {
      final textReporter = nestedReporter ?? reporter;
      final controller = TextEditingController(
        text: '${textReporter.inputs['text'] ?? ''}',
      );
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(catalog.text('editor.textValue')),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop('__REMOVE_REPORTER__'),
              icon: const Icon(Icons.remove_circle_outline),
              label: Text(catalog.text('editor.removeReporter')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(catalog.text('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(catalog.text('common.ok')),
            ),
          ],
        ),
      );
      if (text == '__REMOVE_REPORTER__') {
        engine.removeReporterInput(node, slot.inputKey);
        return;
      }
      if (text != null) {
        if (nestedReporter != null && nestedKey != null) {
          engine.updateNestedReporterInput(
            node,
            slot.inputKey,
            reporter,
            nestedKey,
            nestedReporter,
            'text',
            text,
          );
        } else {
          engine.updateReporterInput(
            node,
            slot.inputKey,
            textReporter,
            'text',
            text,
          );
        }
      }
    }
  }

  Color _colorForNodeType(BlockType type) {
    return _sqlColorForType(type);
  }

  String _labelMaskWithSlotSpacing({
    required BlockNode node,
    required String template,
    required Map<String, dynamic> values,
    required SqlAbstractionMode mode,
    required String localeCode,
    required TextStyle style,
  }) {
    final pattern = RegExp(r'(\[[^\]]+\]|\{[^}]+\})');
    final buffer = StringBuffer();
    var cursor = 0;
    final spaceWidth = _measureText(' ', style);
    final safeSpaceWidth = spaceWidth <= 0 ? 4.0 : spaceWidth;

    for (final m in pattern.allMatches(template)) {
      final before = template.substring(cursor, m.start);
      buffer.write(before);
      final token = m.group(0)!;
      final rawKey = token.substring(1, token.length - 1).trim();
      final inputKey = _slotInputKey(rawKey);
      final leadingGap = _slotLeadingGap(before, inputKey);
      if (leadingGap > 0) {
        buffer.write(' ' * (leadingGap / safeSpaceWidth).ceil());
      }
      final display = _slotDisplay(values[inputKey], rawKey, localeCode, mode);
      final reporter = reporterForInput(node, inputKey);
      final slotWidth = _slotWidthForContent(
        display,
        reporter,
        style,
        localeCode,
        mode,
        inputKey: inputKey,
      );
      final reservedChars =
          (_reservedInlineSlotWidth(slotWidth, inputKey) / safeSpaceWidth)
              .ceil();
      buffer.write(' ' * reservedChars);
      cursor = m.end;
    }

    buffer.write(template.substring(cursor));
    return buffer.toString();
  }

  _InlineNodeLayout _computeInlineLayout({
    required BlockNode node,
    required String template,
    required Map<String, dynamic> values,
    required double maxWidth,
    required SqlAbstractionMode mode,
    required String localeCode,
    required TextStyle style,
  }) {
    final pattern = RegExp(r'(\[[^\]]+\]|\{[^}]+\})');
    final textRuns = <_InlineTextRun>[];
    final slots = <_InlineSlotRect>[];
    var x = 0.0;
    var y = 0.0;
    var cursor = 0;

    void appendText(String text) {
      if (text.isEmpty) return;
      final lines = text.split('\n');
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        if (line.isNotEmpty) {
          textRuns.add(_InlineTextRun(text: line, offset: Offset(x, y)));
          x += _measureText(line, style);
        }
        if (index < lines.length - 1) {
          y += _inlineLineHeight;
          x = 0;
        }
      }
    }

    for (final m in pattern.allMatches(template)) {
      final before = template.substring(cursor, m.start);
      appendText(before);

      final token = m.group(0)!;
      final rawKey = token.substring(1, token.length - 1).trim();
      final inputKey = _slotInputKey(rawKey);
      x += _slotLeadingGap(before, inputKey);
      final display = _slotDisplay(values[inputKey], rawKey, localeCode, mode);
      final reporter = reporterForInput(node, inputKey);
      final slotWidth = _slotWidthForContent(
        display,
        reporter,
        style,
        localeCode,
        mode,
        inputKey: inputKey,
      );
      final slotHeight = reporter == null ? 20.0 : 34.0;
      if (x < maxWidth) {
        slots.add(
          _InlineSlotRect(
            rawKey: rawKey,
            inputKey: inputKey,
            display: display,
            reporter: reporter,
            rect: Rect.fromLTWH(
              x,
              y - (reporter == null ? 0 : 7),
              slotWidth,
              slotHeight,
            ),
          ),
        );
      }
      x += _reservedInlineSlotWidth(slotWidth, inputKey);
      cursor = m.end;
    }
    appendText(template.substring(cursor));
    return _InlineNodeLayout(textRuns: textRuns, slots: slots);
  }

  double _computeBlockWidth({
    required BlockNode node,
    required String template,
    required Map<String, dynamic> values,
    required SqlAbstractionMode mode,
    required String localeCode,
    required TextStyle style,
  }) {
    final pattern = RegExp(r'(\[[^\]]+\]|\{[^}]+\})');
    var lineWidth = 0.0;
    var maxLineWidth = 0.0;
    var cursor = 0;
    for (final m in pattern.allMatches(template)) {
      final before = template.substring(cursor, m.start);
      final lines = before.split('\n');
      if (lines.length > 1) {
        lineWidth += _measureText(lines.first, style);
        if (lineWidth > maxLineWidth) maxLineWidth = lineWidth;
        for (final middle in lines.skip(1).take(lines.length - 2)) {
          final middleWidth = _measureText(middle, style);
          if (middleWidth > maxLineWidth) maxLineWidth = middleWidth;
        }
        lineWidth = _measureText(lines.last, style);
      } else {
        lineWidth += _measureText(before, style);
      }
      final token = m.group(0)!;
      final rawKey = token.substring(1, token.length - 1).trim();
      final inputKey = _slotInputKey(rawKey);
      final display = _slotDisplay(values[inputKey], rawKey, localeCode, mode);
      lineWidth +=
          _slotLeadingGap(before, inputKey) +
          _reservedInlineSlotWidth(
            _slotWidthForContent(
              display,
              reporterForInput(node, inputKey),
              style,
              localeCode,
              mode,
              inputKey: inputKey,
            ),
            inputKey,
          );
      cursor = m.end;
    }
    final trailing = template.substring(cursor);
    final trailingLines = trailing.split('\n');
    if (trailingLines.length > 1) {
      lineWidth += _measureText(trailingLines.first, style);
      if (lineWidth > maxLineWidth) maxLineWidth = lineWidth;
      for (final line in trailingLines.skip(1)) {
        final trailingWidth = _measureText(line, style);
        if (trailingWidth > maxLineWidth) maxLineWidth = trailingWidth;
      }
    } else {
      lineWidth += _measureText(trailing, style);
      if (lineWidth > maxLineWidth) maxLineWidth = lineWidth;
    }
    return maxLineWidth + (template.contains('\n') ? 52 : 28);
  }

  double _heightForNodeContent({
    required double baseHeight,
    required String template,
    required List<_InlineSlotRect> slotRects,
    required List<_InlineTextRun> textRuns,
    required bool isJoin,
  }) {
    final lineCount = template.split('\n').length;
    final labelHeight = 18.0 + (lineCount * (isJoin ? 24.0 : 21.0));
    final slotBottom = slotRects.fold<double>(
      0,
      (maxBottom, slot) => math.max(
        maxBottom,
        9 +
            slot.rect.bottom +
            12 +
            (isJoin && slot.rect.top >= _inlineLineHeight
                ? _joinSecondLineOffset
                : 0),
      ),
    );

    final textBottom = textRuns.fold<double>(
      0,
      (maxBottom, run) => math.max(
        maxBottom,
        9 +
            run.offset.dy +
            20 +
            (isJoin && run.offset.dy >= _inlineLineHeight
                ? _joinSecondLineOffset
                : 0),
      ),
    );
    return math.max(
      baseHeight,
      math.max(labelHeight, math.max(slotBottom, textBottom)),
    );
  }

  double _slotWidthForDisplay(String display, TextStyle style) {
    return (_measureText(display, style.copyWith(fontSize: 12)) + 18).clamp(
      54.0,
      520.0,
    );
  }

  double _slotWidthForContent(
    String display,
    BlockNode? reporter,
    TextStyle style,
    String localeCode,
    SqlAbstractionMode mode, {
    String? inputKey,
  }) {
    if (reporter == null) return _slotWidthForDisplay(display, style);
    final label = _reporterLabelForSlot(reporter, localeCode, mode, inputKey);
    return (_measureText(label, style) + 40).clamp(82.0, 520.0);
  }

  double _reservedInlineSlotWidth(double slotWidth, String inputKey) {
    final safetyGap = switch (inputKey) {
      'columns' ||
      'column' ||
      'column_name' ||
      'where_column' ||
      'left_column' ||
      'right_column' ||
      'condition_column' => 14.0,
      'aggregate' || 'operator' => 10.0,
      _ => 8.0,
    };
    return slotWidth + _slotGap() + safetyGap;
  }

  double _measureText(String text, TextStyle style) {
    return _measureSingleLineText(text, style);
  }

  String _slotDisplay(
    dynamic value,
    String rawKey,
    String localeCode,
    SqlAbstractionMode mode,
  ) {
    final text = '${value ?? ''}'.trim();
    final rawLower = rawKey.toLowerCase();
    final normalized = text.toLowerCase();
    if (text.isEmpty) return '';
    if (normalized == rawLower) return '';
    if (normalized == 'table_name' ||
        normalized == 'column' ||
        normalized == 'spalte' ||
        normalized == 'column_name' ||
        normalized == 'spaltenname' ||
        normalized == 'columns') {
      final defaultDisplay = _slotDefaultDisplay(rawKey);
      if (mode == SqlAbstractionMode.simple &&
          _slotInputKey(rawKey) == 'columns' &&
          defaultDisplay == '*') {
        return simpleAllColumnsLabel(localeCode);
      }
      return defaultDisplay;
    }
    if (_slotInputKey(rawKey) == 'order') {
      return _localizedOrderLabel(_normalizeOrderValue(text), localeCode);
    }
    if (_slotInputKey(rawKey) == 'join_type') {
      return _normalizeJoinValue(text);
    }
    if (_slotInputKey(rawKey) == 'operator') {
      return _normalizeOperatorValue(text);
    }
    if (_slotInputKey(rawKey) == 'aggregate') {
      return _normalizeAggregateValue(text);
    }
    if (_slotInputKey(rawKey) == 'columns') {
      if (mode == SqlAbstractionMode.simple && text == '*') {
        return simpleAllColumnsLabel(localeCode);
      }
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
      case 'Spalten':
        return '*';
      case 'column':
      case 'Spalte':
      case 'column_name':
      case 'Spaltenname':
      case 'where_column':
      case 'Filter_Spalte':
      case 'left_column':
      case 'linke_Spalte':
      case 'right_column':
      case 'rechte_Spalte':
      case 'condition_column':
      case 'Bedingungs_Spalte':
        return 'id';
      case 'operator':
        return '=';
      case 'aggregate':
        return 'COUNT';
      case 'value':
      case 'where_value':
      case 'condition_value':
        return '1';
      case 'table':
      case 'table_name':
        return '';
      case 'column_definitions':
      case 'Spaltendefinitionen':
        return 'id INTEGER PRIMARY KEY';
      case 'ASC|DESC':
      case 'aufsteigend|absteigend':
        return 'ASC';
      default:
        return '';
    }
  }

  double _slotGap() => 14.0;

  double _slotLeadingGap(String precedingText, String inputKey) {
    if (inputKey == 'table' && precedingText.trim().isNotEmpty) {
      return 12.0;
    }
    return 0.0;
  }

  String? _inputKey(BlockNode node) {
    if (node.type == BlockType.sqlWhere) return 'predicate';
    if (node.type == BlockType.sqlOrderBy) return 'expr';
    if (node.type == BlockType.sqlGroupBy) return 'expr';
    if (node.type == BlockType.sqlHaving) return 'value';
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
    final catalog = translationCatalogOf(context);
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
            child: Text(catalog.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(catalog.text('common.ok')),
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
    final catalog = translationCatalogOf(context);
    final mappedKey = _slotInputKey(slotKey);
    if (mappedKey == 'columns') {
      final selectedTable =
          '${node.inputs['table'] ?? engine.contextTableForNode(node.id) ?? ''}';
      final picked = await _pickColumnsDialog(
        context: context,
        columns: _availableColumns(node, runtime, engine),
        currentValue: '${node.inputs[mappedKey] ?? '*'}',
        selectedTable: selectedTable,
        localeCode: localeCode,
      );
      if (picked != null) {
        engine.updateInput(node, mappedKey, picked);
      }
      return;
    }
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
        header: _inlineOptionHeader(
          mappedKey: mappedKey,
          node: node,
          engine: engine,
          localeCode: localeCode,
        ),
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
            child: Text(catalog.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(catalog.text('common.ok')),
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
      'Spalte',
      'column_name',
      'Spaltenname',
      'where_column',
      'Filter_Spalte',
      'left_column',
      'linke_Spalte',
      'right_column',
      'rechte_Spalte',
      'condition_column',
      'Bedingungs_Spalte',
      'columns',
      'Spalten',
      'aggregate',
      'operator',
      'JOIN_TYPE',
      'datatype',
      'ASC|DESC',
      'aufsteigend|absteigend',
      'privilege',
    };
    final dropdownMapped = <String>{
      'table',
      'column',
      'Spalte',
      'column_name',
      'Spaltenname',
      'where_column',
      'Filter_Spalte',
      'left_column',
      'linke_Spalte',
      'right_column',
      'rechte_Spalte',
      'condition_column',
      'Bedingungs_Spalte',
      'columns',
      'Spalten',
      'aggregate',
      'operator',
      'join_type',
      'datatype',
      'order',
      'privilege',
    };
    return dropdownRaw.contains(rawToken) || dropdownMapped.contains(mappedKey);
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
      case 'Spaltendefinitionen':
        return 'definition';
      case 'Spalten':
        return 'columns';
      case 'Spalte':
        return 'column';
      case 'Spaltenname':
        return 'column_name';
      case 'Filter_Spalte':
        return 'where_column';
      case 'linke_Spalte':
        return 'left_column';
      case 'rechte_Spalte':
        return 'right_column';
      case 'Bedingungs_Spalte':
        return 'condition_column';
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
        mappedKey == 'column_name' ||
        mappedKey == 'where_column' ||
        mappedKey == 'left_column' ||
        mappedKey == 'right_column' ||
        mappedKey == 'condition_column') {
      final cols = _availableColumnsForKey(node, mappedKey, runtime, engine);
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

    if (mappedKey == 'aggregate') {
      return const <String>['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];
    }

    if (mappedKey == 'operator') {
      return const <String>['=', '!=', '<>', '>', '>=', '<', '<=', 'LIKE'];
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

  String? _inlineOptionHeader({
    required String mappedKey,
    required BlockNode node,
    required WorkspaceController engine,
    required String localeCode,
  }) {
    final de = _normalizedLocaleCode(localeCode) == 'de';
    if (mappedKey == 'left_column') {
      final table = engine.contextTableBeforeNode(node.id);
      return de
          ? 'Spalte aus Tabelle 1: ${table ?? 'bisherige Tabelle'}'
          : 'Column from table 1: ${table ?? 'previous table'}';
    }
    if (mappedKey == 'right_column') {
      final table = '${node.inputs['table'] ?? ''}'.trim();
      return de
          ? 'Spalte aus Tabelle 2: ${table.isEmpty ? 'Join-Tabelle' : table}'
          : 'Column from table 2: ${table.isEmpty ? 'join table' : table}';
    }
    return null;
  }

  List<String> _availableColumns(
    BlockNode node,
    SqlRuntimeState runtime,
    WorkspaceController engine,
  ) {
    final selectedTable =
        '${node.inputs['table'] ?? engine.contextTableForNode(node.id) ?? ''}';
    final schema = runtime.schemas.where((s) => s.name == selectedTable);
    return schema.isEmpty
        ? runtime.schemas
              .expand((s) => s.columns)
              .toSet()
              .toList(growable: false)
        : schema.first.columns;
  }

  List<String> _availableColumnsForKey(
    BlockNode node,
    String mappedKey,
    SqlRuntimeState runtime,
    WorkspaceController engine,
  ) {
    if (mappedKey == 'left_column') {
      final table = engine.contextTableBeforeNode(node.id);
      return _qualifiedColumnsForTable(runtime, table);
    }
    if (mappedKey == 'right_column') {
      final table = '${node.inputs['table'] ?? ''}'.trim();
      return _qualifiedColumnsForTable(runtime, table);
    }
    return _availableColumns(node, runtime, engine);
  }

  List<String> _qualifiedColumnsForTable(
    SqlRuntimeState runtime,
    String? tableInput,
  ) {
    final table = tableInput?.trim() ?? '';
    if (table.isEmpty || table == 'table_name') {
      return runtime.schemas
          .expand(
            (schema) =>
                schema.columns.map((column) => '${schema.name}.$column'),
          )
          .toSet()
          .toList(growable: false);
    }
    final schemaName = _schemaNameFromTableInput(table);
    final qualifier = _columnQualifierFromTableInput(table);
    final schema = runtime.schemas.where((s) => s.name == schemaName);
    if (schema.isEmpty) {
      return runtime.schemas
          .expand((s) => s.columns.map((column) => '${s.name}.$column'))
          .toSet()
          .toList(growable: false);
    }
    return schema.first.columns
        .map((column) => '$qualifier.$column')
        .toList(growable: false);
  }

  String _schemaNameFromTableInput(String tableInput) {
    final parts = tableInput.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? tableInput.trim() : parts.first;
  }

  String _columnQualifierFromTableInput(String tableInput) {
    final parts = tableInput.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[parts.length - 2].toLowerCase() == 'as') {
      return parts.last;
    }
    if (parts.length >= 2) return parts.last;
    return _schemaNameFromTableInput(tableInput);
  }

  Future<String?> _pickColumnsDialog({
    required BuildContext context,
    required List<String> columns,
    required String currentValue,
    required String selectedTable,
    required String localeCode,
  }) {
    final catalog = translationCatalogOf(context);
    var selectAll = currentValue.trim() == '*';
    final selectedColumns = _selectedColumns(currentValue).toSet();

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            catalog.text('editor.chooseColumn', {'table': selectedTable}),
          ),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView(
              children: [
                CheckboxListTile(
                  value: selectAll,
                  secondary: const Icon(Icons.select_all),
                  title: Text(simpleAllColumnsLabel(localeCode)),
                  onChanged: (selected) {
                    setDialogState(() {
                      selectAll = selected == true;
                      if (selectAll) selectedColumns.clear();
                    });
                  },
                ),
                if (columns.isNotEmpty) const Divider(height: 1),
                for (final column in columns)
                  CheckboxListTile(
                    value: selectedColumns.contains(column),
                    secondary: const Icon(Icons.view_column_outlined),
                    title: Text(column),
                    onChanged: selectAll
                        ? null
                        : (selected) {
                            setDialogState(() {
                              if (selected == true) {
                                selectedColumns.add(column);
                              } else {
                                selectedColumns.remove(column);
                              }
                            });
                          },
                  ),
                if (columns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(catalog.text('editor.noSchemaOptions')),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(catalog.text('common.cancel')),
            ),
            FilledButton(
              onPressed: selectAll || selectedColumns.isNotEmpty
                  ? () => Navigator.of(
                      context,
                    ).pop(selectAll ? '*' : selectedColumns.join(', '))
                  : null,
              child: Text(catalog.text('common.ok')),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickInlineOptionOverlay({
    required BuildContext context,
    required List<String> options,
    required Offset anchorGlobal,
    required String localeCode,
    String? header,
  }) async {
    final catalog = translationCatalogOf(context);
    final completer = Completer<String?>();
    final textController = TextEditingController();
    OverlayEntry? entry;

    void close([String? value]) {
      entry?.remove();
      if (!completer.isCompleted) completer.complete(value);
      textController.dispose();
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.4;
    final overlayWidth = options.any(_isJoinOption) ? 340.0 : 240.0;
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final anchor = overlayBox.globalToLocal(anchorGlobal);
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    final foreground = Theme.of(context).colorScheme.onSurface;
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
            left: _clampOverlayLeft(
              context,
              anchor.dx - overlayWidth / 2,
              overlayWidth,
            ),
            top: _clampOverlayTop(context, anchor.dy + 8, maxHeight),
            child: Material(
              color: Colors.transparent,
              child: Container(
                key: const ValueKey('inline-option-overlay'),
                width: overlayWidth,
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: workbenchColors.panelElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: workbenchColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (header != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: workbenchColors.panel,
                                border: Border(
                                  bottom: BorderSide(
                                    color: workbenchColors.border,
                                  ),
                                ),
                              ),
                              child: Text(
                                header,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: workbenchColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Flexible(
                            child: options.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        catalog.text('editor.noSchemaOptions'),
                                        style: TextStyle(
                                          color: workbenchColors.muted,
                                        ),
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
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _localizedOptionLabel(
                                                        options[i],
                                                        localeCode,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: foreground,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    if (_localizedOptionSubtitle(
                                                          options[i],
                                                          localeCode,
                                                        )
                                                        case final subtitle?)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 2,
                                                            ),
                                                        child: Text(
                                                          subtitle,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color:
                                                                workbenchColors
                                                                    .muted,
                                                            fontSize: 12,
                                                            height: 1.15,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
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
                        ],
                      ),
                    ),
                    Divider(height: 1, color: workbenchColors.border),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textController,
                              style: TextStyle(color: foreground),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: catalog.text('editor.customValue'),
                                hintStyle: TextStyle(
                                  color: workbenchColors.muted,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: () => close(textController.text.trim()),
                            icon: Icon(Icons.check, color: foreground),
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

    overlay.insert(entry);
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
    if (value == '*') {
      return simpleAllColumnsLabel(localeCode);
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
    if (joins.contains(value)) return _localizedJoinTitle(value, localeCode);
    return value;
  }

  bool _isJoinOption(String value) {
    const joins = <String>{
      'INNER',
      'LEFT',
      'RIGHT',
      'FULL',
      'CROSS',
      'NATURAL',
      'SELF',
    };
    return joins.contains(value);
  }

  String? _localizedOptionSubtitle(String value, String localeCode) {
    if (!_isJoinOption(value)) return null;
    return _localizedJoinSubtitle(value, localeCode);
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

  String _localizedJoinTitle(String value, String localeCode) {
    return switch (value) {
      'INNER' => 'Inner Join',
      'LEFT' => 'Left Join',
      'RIGHT' => 'Right Join',
      'FULL' => 'Full Join',
      'CROSS' => 'Cross Join',
      'NATURAL' => 'Natural Join',
      'SELF' => 'Self Join',
      _ => value,
    };
  }

  String _localizedJoinSubtitle(String value, String localeCode) {
    final code = _normalizedLocaleCode(localeCode);
    switch (value) {
      case 'INNER':
        return switch (code) {
          'de' => 'Nur Zeilen, die in beiden Tabellen passen.',
          'es' => 'Inner Join (coincidencias en ambas tablas)',
          'fr' => 'Inner Join (lignes présentes dans les deux tables)',
          _ => 'Only rows that match in both tables.',
        };
      case 'LEFT':
        return switch (code) {
          'de' => 'Alle bisherigen Zeilen bleiben, passende neue kommen dazu.',
          'es' => 'Left Join (todas filas izquierdas + coincidencias)',
          'fr' => 'Left Join (toutes lignes gauche + correspondances)',
          _ => 'Keep all previous rows and add matching new rows.',
        };
      case 'RIGHT':
        return switch (code) {
          'de' => 'Alle Zeilen der neuen Tabelle bleiben erhalten.',
          'es' => 'Right Join (todas filas derechas + coincidencias)',
          'fr' => 'Right Join (toutes lignes droite + correspondances)',
          _ => 'Keep all rows from the new table.',
        };
      case 'FULL':
        return switch (code) {
          'de' => 'Alle Zeilen aus beiden Tabellen bleiben erhalten.',
          'es' => 'Full Join (todas las filas de ambas tablas)',
          'fr' => 'Full Join (toutes les lignes des deux tables)',
          _ => 'Keep all rows from both tables.',
        };
      case 'CROSS':
        return switch (code) {
          'de' =>
            'Kombiniert jede Zeile mit jeder Zeile. Sehr viele Ergebnisse möglich.',
          'es' => 'Cross Join (combina cada fila con todas)',
          'fr' => 'Cross Join (chaque ligne combinée avec toutes)',
          _ => 'Combine every row with every row. Can create many results.',
        };
      case 'NATURAL':
        return switch (code) {
          'de' => 'Verbindet automatisch über gleich benannte Spalten.',
          'es' => 'Natural Join (automático por columnas iguales)',
          'fr' => 'Natural Join (automatique par colonnes identiques)',
          _ => 'Automatically joins columns with the same names.',
        };
      case 'SELF':
        return switch (code) {
          'de' => 'Vergleicht eine Tabelle mit sich selbst.',
          'es' => 'Self Join (unir tabla consigo misma)',
          'fr' => 'Self Join (joindre la table à elle-même)',
          _ => 'Compare a table with itself.',
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

  String _normalizeAggregateValue(String input) {
    final normalized = input.trim().toUpperCase();
    const known = <String>{'COUNT', 'SUM', 'AVG', 'MIN', 'MAX'};
    return known.contains(normalized) ? normalized : 'COUNT';
  }

  String _normalizeOperatorValue(String input) {
    final normalized = input.trim().toUpperCase();
    const known = <String>{
      '=',
      '!=',
      '<>',
      '>',
      '>=',
      '<',
      '<=',
      'LIKE',
      'NOT LIKE',
    };
    if (known.contains(normalized)) return normalized;
    if (normalized == '=>') return '>=';
    if (normalized == '=<') return '<=';
    if (normalized == '==' || normalized == 'IST' || normalized == 'IS') {
      return '=';
    }
    return '=';
  }

  String _normalizeInputValue(String mappedKey, String value) {
    if (mappedKey == 'order') return _normalizeOrderValue(value);
    if (mappedKey == 'join_type') return _normalizeJoinValue(value);
    if (mappedKey == 'operator') return _normalizeOperatorValue(value);
    if (mappedKey == 'aggregate') return _normalizeAggregateValue(value);
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
    required this.reporter,
    required this.rect,
  });

  final String rawKey;
  final String inputKey;
  final String display;
  final BlockNode? reporter;
  final Rect rect;
}

class _InlineTextRun {
  const _InlineTextRun({required this.text, required this.offset});

  final String text;
  final Offset offset;
}

class _InlineNodeLayout {
  const _InlineNodeLayout({required this.textRuns, required this.slots});

  final List<_InlineTextRun> textRuns;
  final List<_InlineSlotRect> slots;
}

class _ColumnReporterEditResult {
  const _ColumnReporterEditResult({this.value, this.removeReporter = false});

  final String? value;
  final bool removeReporter;
}

class _NodeDiagnosticBadge extends StatelessWidget {
  const _NodeDiagnosticBadge({required this.diagnostic});

  final _SimpleNodeDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${diagnostic.title}\n${diagnostic.message}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF991B1B).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFFCA5A5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 15,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                diagnostic.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SqlRuntimePane extends StatefulWidget {
  const _SqlRuntimePane({
    required this.sql,
    required this.runtime,
    required this.mode,
    required this.localeCode,
    required this.catalog,
  });

  final String sql;
  final SqlRuntimeState runtime;
  final SqlAbstractionMode mode;
  final String localeCode;
  final TranslationCatalog catalog;

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
    final copied = widget.catalog.text('runtime.copied');
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final workbenchColors = NodeQlWorkbenchColors.of(context);
        final sql = widget.sql.isEmpty
            ? widget.catalog.text('runtime.sqlOutput')
            : widget.sql;
        final lineCount = '\n'.allMatches(sql).length + 1;
        final desiredSqlHeight = 48.0 + 28.0 + (lineCount * 19.0);
        final maxSqlHeight = (constraints.maxHeight * 0.58).clamp(130.0, 420.0);
        final sqlHeight = desiredSqlHeight.clamp(112.0, maxSqlHeight);
        return Column(
          key: const ValueKey('split'),
          children: [
            SizedBox(
              height: sqlHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: workbenchColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: workbenchColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      height: 48,
                      padding: const EdgeInsets.only(left: 14, right: 4),
                      decoration: BoxDecoration(
                        color: workbenchColors.panelElevated,
                        border: Border(
                          bottom: BorderSide(color: workbenchColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.terminal_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              widget.catalog.text('runtime.sqlCommandOutput'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('copy-sql-command'),
                            onPressed: widget.sql.trim().isEmpty
                                ? null
                                : _copySqlToClipboard,
                            color: Theme.of(context).colorScheme.onSurface,
                            tooltip: widget.catalog.text('runtime.copySql'),
                            icon: const Icon(Icons.copy_rounded, size: 19),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          child: SelectionArea(
                            child: Text(
                              sql,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: workbenchColors.sqlText,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildOutputBody()),
          ],
        );
      },
    );
  }

  Widget _buildOutputBody() {
    final workbenchColors = NodeQlWorkbenchColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.runtime.lastRows.isEmpty) {
      final message = widget.runtime.lastMessage == null
          ? widget.catalog.text('runtime.noResults')
          : _friendlyVisibleRuntimeMessage(
              mode: widget.mode,
              message: widget.runtime.lastMessage!,
            );
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: workbenchColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: workbenchColors.border),
        ),
        child: Text(message, style: TextStyle(color: colorScheme.onSurface)),
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
                headingTextStyle: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: TextStyle(color: colorScheme.onSurface),
                headingRowColor: WidgetStateProperty.all(
                  workbenchColors.panelElevated,
                ),
                dataRowColor: WidgetStateProperty.all(workbenchColors.panel),
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
