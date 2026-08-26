import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nodeql/core/theme/theme_controller.dart';
import 'package:nodeql/features/workbench/presentation/engine/database_browser.dart';
import 'package:nodeql/features/workbench/presentation/engine/sql_mode.dart';
import 'package:nodeql/localization/translation_catalog.dart';
import 'package:path/path.dart' as p;

typedef DatabaseOverviewLoader = Future<DatabaseOverview> Function(String path);
typedef DatabaseObjectLoader =
    Future<DatabaseObjectSnapshot> Function(
      String path,
      String objectName,
      int limit,
      int offset,
    );

Widget _clipDatabaseSurface({
  required BuildContext context,
  required BorderRadius borderRadius,
  required Widget child,
  Key? key,
}) {
  if (NodeQlSurfaceStyle.of(context).isBrutalist) return child;
  return ClipRRect(
    key: key,
    borderRadius: borderRadius,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

DatabaseOverview _loadDatabaseOverview(String path) =>
    const SqliteDatabaseBrowser().loadOverview(path);

DatabaseObjectSnapshot _loadDatabaseObject(
  ({String path, String objectName, int limit, int offset}) request,
) => const SqliteDatabaseBrowser().loadObject(
  request.path,
  request.objectName,
  limit: request.limit,
  offset: request.offset,
);

class DatabaseBrowserWorker {
  const DatabaseBrowserWorker();

  Future<DatabaseOverview> loadOverview(String path) =>
      compute(_loadDatabaseOverview, path);

  Future<DatabaseObjectSnapshot> loadObject(
    String path,
    String objectName,
    int limit,
    int offset,
  ) => compute(_loadDatabaseObject, (
    path: path,
    objectName: objectName,
    limit: limit,
    offset: offset,
  ));
}

class DatabaseBrowserDialog extends StatefulWidget {
  const DatabaseBrowserDialog({
    required this.databasePath,
    required this.catalog,
    this.initialMode = SqlAbstractionMode.advanced,
    this.onModeChanged,
    this.overviewLoader,
    this.objectLoader,
    super.key,
  });

  final String databasePath;
  final TranslationCatalog catalog;
  final SqlAbstractionMode initialMode;
  final ValueChanged<SqlAbstractionMode>? onModeChanged;
  final DatabaseOverviewLoader? overviewLoader;
  final DatabaseObjectLoader? objectLoader;

  @override
  State<DatabaseBrowserDialog> createState() => _DatabaseBrowserDialogState();
}

class _DatabaseBrowserDialogState extends State<DatabaseBrowserDialog> {
  static const _pageSize = 100;

  final TextEditingController _searchController = TextEditingController();
  DatabaseOverview? _overview;
  DatabaseObjectSnapshot? _snapshot;
  String? _selectedName;
  String? _error;
  bool _loadingOverview = true;
  bool _loadingObject = false;
  int _requestNumber = 0;
  String _searchQuery = '';
  late SqlAbstractionMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    unawaited(_loadOverview());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _modeText(
    String advancedKey,
    String simpleKey, [
    Map<String, Object?> values = const {},
  ]) => widget.catalog.text(
    _mode == SqlAbstractionMode.simple ? simpleKey : advancedKey,
    values,
  );

  Future<void> _loadOverview({String? preferredName}) async {
    setState(() {
      _loadingOverview = true;
      _error = null;
    });
    try {
      final path = widget.databasePath;
      final loader =
          widget.overviewLoader ?? const DatabaseBrowserWorker().loadOverview;
      final overview = await loader(path);
      if (!mounted) return;
      final selected =
          overview.objects.any((object) => object.name == preferredName)
          ? preferredName
          : overview.objects.firstOrNull?.name;
      setState(() {
        _overview = overview;
        _selectedName = selected;
        _snapshot = null;
        _loadingOverview = false;
      });
      if (selected != null) await _loadObject(selected, offset: 0);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingOverview = false;
        _error = '$error';
      });
    }
  }

  Future<void> _loadObject(String name, {required int offset}) async {
    final requestNumber = ++_requestNumber;
    setState(() {
      _selectedName = name;
      _loadingObject = true;
      _error = null;
    });
    try {
      final path = widget.databasePath;
      final loader =
          widget.objectLoader ?? const DatabaseBrowserWorker().loadObject;
      final snapshot = await loader(path, name, _pageSize, offset);
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _snapshot = snapshot;
        _loadingObject = false;
      });
    } on Object catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _loadingObject = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final showModeInHeader = size.width >= 1300;
    Widget content = SizedBox(
      key: const ValueKey<String>('database-browser-dialog'),
      width: (size.width * .94).clamp(680, 1240),
      height: (size.height * .9).clamp(480, 900),
      child: Column(
        children: [
          _buildHeader(context, showModeSwitch: showModeInHeader),
          if (!showModeInHeader) _buildModeSwitch(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
    if (!surfaceStyle.isBrutalist) {
      final theme = Theme.of(context);
      content = ClipRRect(
        key: const ValueKey<String>('database-browser-surface-clip'),
        borderRadius: surfaceStyle.largeBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: Material(
          key: const ValueKey<String>('database-browser-surface-background'),
          color: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          child: content,
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: surfaceStyle.isBrutalist ? null : Colors.transparent,
      elevation: surfaceStyle.isBrutalist ? null : 0,
      shadowColor: surfaceStyle.isBrutalist ? null : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: surfaceStyle.largeBorderRadius,
      ),
      child: content,
    );
  }

  Widget _buildModeSwitch(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Center(child: _buildModeControl(context)),
    );
  }

  Widget _buildModeControl(BuildContext context, {BorderRadius? borderRadius}) {
    return SegmentedButton<SqlAbstractionMode>(
      key: const ValueKey<String>('database-browser-mode'),
      showSelectedIcon: false,
      style: borderRadius == null
          ? null
          : ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: borderRadius),
              ),
            ),
      segments: [
        ButtonSegment<SqlAbstractionMode>(
          value: SqlAbstractionMode.simple,
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: Text(widget.catalog.text('toolbar.simple')),
        ),
        ButtonSegment<SqlAbstractionMode>(
          value: SqlAbstractionMode.advanced,
          icon: const Icon(Icons.schema_outlined, size: 18),
          label: Text(widget.catalog.text('toolbar.advanced')),
        ),
      ],
      selected: <SqlAbstractionMode>{_mode},
      onSelectionChanged: (selection) {
        final next = selection.first;
        setState(() => _mode = next);
        widget.onModeChanged?.call(next);
      },
    );
  }

  Widget _buildHeader(BuildContext context, {required bool showModeSwitch}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final headerControlRadius = surfaceStyle.innerBorderRadius(
      outerRadius: surfaceStyle.radiusLarge,
      gap: 14,
    );
    final overview = _overview;

    return ClipRRect(
      borderRadius: surfaceStyle.largeBorderRadius,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 12, 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            _clipDatabaseSurface(
              context: context,
              key: const ValueKey<String>('database-browser-header-icon-clip'),
              borderRadius: headerControlRadius,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: headerControlRadius,
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: colors.onPrimaryContainer,
                  size: 23,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(widget.databasePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Tooltip(
                    message: widget.databasePath,
                    child: Text(
                      _modeText(
                        'databaseBrowser.title',
                        'databaseBrowser.simple.title',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showModeSwitch) ...[
              const SizedBox(width: 20),
              _buildModeControl(context, borderRadius: headerControlRadius),
              const SizedBox(width: 16),
            ],
            if (overview != null)
              _InfoPill(
                icon: Icons.dataset_outlined,
                borderRadius: headerControlRadius,
                label: widget.catalog.text('databaseBrowser.objectCount', {
                  'count': overview.objects.length,
                }),
              ),
            const SizedBox(width: 6),
            _clipDatabaseSurface(
              context: context,
              key: const ValueKey<String>('database-browser-refresh-clip'),
              borderRadius: headerControlRadius,
              child: IconButton.filledTonal(
                key: const ValueKey<String>('database-browser-refresh'),
                onPressed: _loadingOverview
                    ? null
                    : () => _loadOverview(preferredName: _selectedName),
                tooltip: widget.catalog.text('databaseBrowser.refresh'),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(width: 6),
            _clipDatabaseSurface(
              context: context,
              key: const ValueKey<String>('database-browser-close-clip'),
              borderRadius: headerControlRadius,
              child: Material(
                color: const Color(0xFF1ECBE1),
                borderRadius: headerControlRadius,
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: widget.catalog.text('common.close'),
                  icon: const Icon(Icons.close_rounded, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingOverview) {
      return const Center(child: CircularProgressIndicator());
    }
    final overview = _overview;
    if (overview == null) return _buildError(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 286,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(right: BorderSide(color: theme.dividerColor)),
          ),
          child: _buildObjectList(context, overview),
        ),
        Expanded(child: _buildObjectDetails(context, overview)),
      ],
    );
  }

  Widget _buildObjectList(BuildContext context, DatabaseOverview overview) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final matches = overview.objects.where(
      (object) =>
          normalizedQuery.isEmpty ||
          object.name.toLowerCase().contains(normalizedQuery),
    );
    final tables = matches
        .where((object) => object.type == DatabaseObjectType.table)
        .toList(growable: false);
    final views = matches
        .where((object) => object.type == DatabaseObjectType.view)
        .toList(growable: false);
    final hasMatches = tables.isNotEmpty || views.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            key: const ValueKey<String>('database-browser-search'),
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: _modeText(
                'databaseBrowser.search',
                'databaseBrowser.simple.search',
              ),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey<String>(
                        'database-browser-clear-search',
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      tooltip: _modeText(
                        'databaseBrowser.clearSearch',
                        'databaseBrowser.simple.clearSearch',
                      ),
                      icon: const Icon(Icons.clear_rounded, size: 18),
                    ),
              border: OutlineInputBorder(
                borderRadius: NodeQlSurfaceStyle.of(context).mediumBorderRadius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: NodeQlSurfaceStyle.of(context).mediumBorderRadius,
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (tables.isNotEmpty)
                _ObjectSectionLabel(
                  label: _modeText(
                    'databaseBrowser.tables',
                    'databaseBrowser.simple.tables',
                  ),
                  count: tables.length,
                ),
              for (final object in tables) _buildObjectTile(context, object),
              if (views.isNotEmpty)
                _ObjectSectionLabel(
                  label: _modeText(
                    'databaseBrowser.views',
                    'databaseBrowser.simple.views',
                  ),
                  count: views.length,
                ),
              for (final object in views) _buildObjectTile(context, object),
              if (overview.objects.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _modeText(
                      'databaseBrowser.noObjects',
                      'databaseBrowser.simple.noObjects',
                    ),
                  ),
                ),
              if (overview.objects.isNotEmpty && !hasMatches)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.search_off_rounded, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        _modeText(
                          'databaseBrowser.noMatches',
                          'databaseBrowser.simple.noMatches',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _buildDatabaseMetadata(context, overview),
      ],
    );
  }

  Widget _buildObjectTile(BuildContext context, DatabaseObjectSummary object) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final tileRadius = surfaceStyle.mediumBorderRadius;
    final tileIconRadius = surfaceStyle.innerBorderRadius(
      outerRadius: surfaceStyle.radiusMedium,
      gap: 9,
    );
    final selected = _selectedName == object.name;
    final icon = object.type == DatabaseObjectType.table
        ? Icons.table_chart_outlined
        : Icons.visibility_outlined;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: _clipDatabaseSurface(
        context: context,
        key: ValueKey<String>('database-object-${object.name}-clip'),
        borderRadius: tileRadius,
        child: Material(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: tileRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey<String>('database-object-${object.name}'),
            borderRadius: tileRadius,
            onTap: () => _loadObject(object.name, offset: 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  _clipDatabaseSurface(
                    context: context,
                    borderRadius: tileIconRadius,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.secondary.withValues(alpha: .16)
                            : colors.surfaceContainerHigh,
                        borderRadius: tileIconRadius,
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      object.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected ? colors.onSecondaryContainer : null,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSecondaryContainer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDatabaseMetadata(
    BuildContext context,
    DatabaseOverview overview,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: const Icon(Icons.info_outline_rounded, size: 20),
        title: Text(
          _modeText(
            'databaseBrowser.databaseInfo',
            'databaseBrowser.simple.databaseInfo',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        children: [
          DefaultTextStyle(
            style: Theme.of(context).textTheme.bodySmall!,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_modeText('databaseBrowser.encoding', 'databaseBrowser.simple.encoding')}: ${overview.encoding}',
                ),
                Text('user_version: ${overview.userVersion}'),
                Text('application_id: ${overview.applicationId}'),
                Text(
                  '${_modeText('databaseBrowser.size', 'databaseBrowser.simple.size')}: '
                  '${_formatBytes(overview.pageSize * overview.pageCount)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectSummary(
    BuildContext context,
    DatabaseObjectSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final isTable = snapshot.object.type == DatabaseObjectType.table;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      color: colors.surface,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: surfaceStyle.mediumBorderRadius,
            ),
            child: Icon(
              isTable ? Icons.table_chart_outlined : Icons.visibility_outlined,
              color: colors.onPrimaryContainer,
              size: 23,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.object.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _modeText(
                    isTable ? 'databaseBrowser.table' : 'databaseBrowser.view',
                    isTable
                        ? 'databaseBrowser.simple.table'
                        : 'databaseBrowser.simple.view',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoPill(
                icon: Icons.view_column_outlined,
                label: _modeText(
                  'databaseBrowser.columnsCount',
                  'databaseBrowser.simple.columnsCount',
                  {'count': snapshot.columns.length},
                ),
              ),
              _InfoPill(
                icon: Icons.format_list_numbered_rounded,
                label: _modeText(
                  'databaseBrowser.rows',
                  'databaseBrowser.simple.rows',
                  {'count': snapshot.totalRowCount},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildObjectDetails(BuildContext context, DatabaseOverview overview) {
    if (overview.objects.isEmpty) {
      return Center(
        child: Text(
          _modeText(
            'databaseBrowser.noObjects',
            'databaseBrowser.simple.noObjects',
          ),
        ),
      );
    }
    if (_loadingObject && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _buildError(context);
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final tabInnerRadius = surfaceStyle.innerBorderRadius(
      outerRadius: surfaceStyle.radiusMedium,
      gap: 4,
    );
    return DefaultTabController(
      key: ValueKey<String>('database-object-tabs-${snapshot.object.name}'),
      length: 2,
      child: Column(
        children: [
          _buildObjectSummary(context, snapshot),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(4),
            clipBehavior: surfaceStyle.isBrutalist ? Clip.none : Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: surfaceStyle.mediumBorderRadius,
              border: Border.all(color: theme.dividerColor),
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              splashBorderRadius: surfaceStyle.isBrutalist
                  ? null
                  : tabInnerRadius,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: colors.surface,
                borderRadius: tabInnerRadius,
                border: Border.all(color: theme.dividerColor),
              ),
              tabs: [
                Tab(
                  key: const ValueKey<String>('database-browser-content-tab'),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_rows_outlined, size: 18),
                        const SizedBox(width: 7),
                        Text(
                          _modeText(
                            'databaseBrowser.content',
                            'databaseBrowser.simple.content',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Tab(
                  key: const ValueKey<String>('database-browser-structure-tab'),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_tree_outlined, size: 18),
                        const SizedBox(width: 7),
                        Text(
                          _modeText(
                            'databaseBrowser.structure',
                            'databaseBrowser.simple.structure',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loadingObject) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: TabBarView(
              children: [
                _buildContent(context, snapshot),
                _buildStructure(context, snapshot),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, DatabaseObjectSnapshot snapshot) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final paginationInnerRadius = surfaceStyle.innerBorderRadius(
      outerRadius: surfaceStyle.radiusMedium,
      gap: 7,
    );
    final totalPages = snapshot.totalRowCount == 0
        ? 1
        : (snapshot.totalRowCount / snapshot.limit).ceil();
    final currentPage = (snapshot.offset / snapshot.limit).floor() + 1;
    final rangeLabel = snapshot.totalRowCount == 0
        ? _modeText('databaseBrowser.noRows', 'databaseBrowser.simple.noRows')
        : _modeText(
            'databaseBrowser.rowRange',
            'databaseBrowser.simple.rowRange',
            {
              'start': snapshot.offset + 1,
              'end': snapshot.offset + snapshot.rows.length,
              'count': snapshot.totalRowCount,
            },
          );
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 7, 8, 7),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: surfaceStyle.mediumBorderRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  rangeLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: paginationInnerRadius,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey<String>(
                        'database-browser-previous-page',
                      ),
                      onPressed: snapshot.offset == 0 || _loadingObject
                          ? null
                          : () => _loadObject(
                              snapshot.object.name,
                              offset: (snapshot.offset - snapshot.limit).clamp(
                                0,
                                snapshot.totalRowCount,
                              ),
                            ),
                      tooltip: _modeText(
                        'databaseBrowser.previous',
                        'databaseBrowser.simple.previous',
                      ),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _modeText(
                          'databaseBrowser.page',
                          'databaseBrowser.simple.page',
                          {'current': currentPage, 'total': totalPages},
                        ),
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>('database-browser-next-page'),
                      onPressed:
                          snapshot.offset + snapshot.rows.length >=
                                  snapshot.totalRowCount ||
                              _loadingObject
                          ? null
                          : () => _loadObject(
                              snapshot.object.name,
                              offset: snapshot.offset + snapshot.limit,
                            ),
                      tooltip: _modeText(
                        'databaseBrowser.next',
                        'databaseBrowser.simple.next',
                      ),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: snapshot.rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inbox_outlined, size: 40),
                      const SizedBox(height: 10),
                      Text(
                        _modeText(
                          'databaseBrowser.noRows',
                          'databaseBrowser.simple.noRows',
                        ),
                      ),
                    ],
                  ),
                )
              : _buildDataGrid(context, snapshot),
        ),
      ],
    );
  }

  Widget _buildDataGrid(BuildContext context, DatabaseObjectSnapshot snapshot) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: ClipRRect(
        borderRadius: surfaceStyle.mediumBorderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: theme.dividerColor),
            borderRadius: surfaceStyle.mediumBorderRadius,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          colors.surfaceContainerHigh,
                        ),
                        headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                        dividerThickness: .7,
                        horizontalMargin: 18,
                        columnSpacing: 28,
                        dataRowMinHeight: 46,
                        dataRowMaxHeight: 76,
                        columns: [
                          const DataColumn(label: Text('#')),
                          for (final name in snapshot.columnNames)
                            DataColumn(label: Text(name)),
                        ],
                        rows: [
                          for (
                            var rowIndex = 0;
                            rowIndex < snapshot.rows.length;
                            rowIndex++
                          )
                            DataRow(
                              color: WidgetStatePropertyAll(
                                rowIndex.isEven
                                    ? colors.surfaceContainerLowest
                                    : colors.surface,
                              ),
                              cells: [
                                DataCell(
                                  Text(
                                    '${snapshot.offset + rowIndex + 1}',
                                    style: TextStyle(color: colors.outline),
                                  ),
                                ),
                                for (final value in snapshot.rows[rowIndex])
                                  DataCell(
                                    _DatabaseValue(
                                      value: value,
                                      catalog: widget.catalog,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyCreateSql(DatabaseObjectSnapshot snapshot) async {
    final sql = snapshot.object.createSql;
    if (sql.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: sql));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _modeText(
            'databaseBrowser.createSqlCopied',
            'databaseBrowser.simple.createSqlCopied',
          ),
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Widget _buildStructure(
    BuildContext context,
    DatabaseObjectSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _DatabaseSectionTitle(
          icon: Icons.view_column_outlined,
          label: _modeText(
            'databaseBrowser.columns',
            'databaseBrowser.simple.columns',
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: surfaceStyle.mediumBorderRadius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: surfaceStyle.mediumBorderRadius,
              border: Border.all(color: theme.dividerColor),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.surfaceContainerHigh,
                ),
                headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                columns: [
                  DataColumn(
                    label: Text(
                      _modeText(
                        'databaseBrowser.column',
                        'databaseBrowser.simple.column',
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      _modeText(
                        'databaseBrowser.type',
                        'databaseBrowser.simple.type',
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      _modeText(
                        'databaseBrowser.notNull',
                        'databaseBrowser.simple.required',
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      _modeText(
                        'databaseBrowser.defaultValue',
                        'databaseBrowser.simple.defaultValue',
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      _modeText(
                        'databaseBrowser.primaryKey',
                        'databaseBrowser.simple.primaryKey',
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      _modeText(
                        'databaseBrowser.hidden',
                        'databaseBrowser.simple.hidden',
                      ),
                    ),
                  ),
                ],
                rows: [
                  for (final column in snapshot.columns)
                    DataRow(
                      cells: [
                        DataCell(SelectableText(column.name)),
                        DataCell(SelectableText(column.declaredType)),
                        DataCell(Text(column.notNull ? '✓' : '—')),
                        DataCell(SelectableText(column.defaultSql ?? 'NULL')),
                        DataCell(
                          Text(
                            column.primaryKeyOrder == 0
                                ? '—'
                                : '${column.primaryKeyOrder}',
                          ),
                        ),
                        DataCell(Text(_hiddenLabel(column.hidden))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (snapshot.foreignKeys.isNotEmpty) ...[
          const SizedBox(height: 24),
          _DatabaseSectionTitle(
            icon: Icons.link_rounded,
            label: _modeText(
              'databaseBrowser.foreignKeys',
              'databaseBrowser.simple.foreignKeys',
            ),
          ),
          const SizedBox(height: 10),
          for (final key in snapshot.foreignKeys)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.link_rounded),
                title: SelectableText(
                  '${key.fromColumn} → ${key.referencedTable}.${key.toColumn ?? ''}',
                ),
                subtitle: Text(
                  'ON UPDATE ${key.onUpdate}  •  ON DELETE ${key.onDelete}'
                  '${key.match == 'NONE' ? '' : '  •  MATCH ${key.match}'}',
                ),
              ),
            ),
        ],
        if (snapshot.indexes.isNotEmpty) ...[
          const SizedBox(height: 24),
          _DatabaseSectionTitle(
            icon: Icons.speed_rounded,
            label: _modeText(
              'databaseBrowser.indexes',
              'databaseBrowser.simple.indexes',
            ),
          ),
          const SizedBox(height: 10),
          for (final index in snapshot.indexes)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.speed_rounded),
                title: SelectableText(index.name),
                subtitle: Text(
                  index.columns.where((column) => column.isNotEmpty).join(', '),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (index.unique) const _InfoPill(label: 'UNIQUE'),
                    if (index.partial) const _InfoPill(label: 'PARTIAL'),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _DatabaseSectionTitle(
                icon: Icons.code_rounded,
                label: _modeText(
                  'databaseBrowser.createSql',
                  'databaseBrowser.simple.createSql',
                ),
              ),
            ),
            IconButton(
              key: const ValueKey<String>('database-browser-copy-create-sql'),
              onPressed: snapshot.object.createSql.isEmpty
                  ? null
                  : () => _copyCreateSql(snapshot),
              tooltip: _modeText(
                'databaseBrowser.copyCreateSql',
                'databaseBrowser.simple.copyCreateSql',
              ),
              icon: const Icon(Icons.copy_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: surfaceStyle.mediumBorderRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: SelectableText(
            snapshot.object.createSql.isEmpty ? '—' : snapshot.object.createSql,
            style: const TextStyle(fontFamily: 'monospace', height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 10),
            SelectableText(
              widget.catalog.text('databaseBrowser.loadFailed', {
                'error': _error ?? '',
              }),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _hiddenLabel(int hidden) => switch (hidden) {
    1 => 'hidden',
    2 => 'generated (virtual)',
    3 => 'generated (stored)',
    _ => '—',
  };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

class _ObjectSectionLabel extends StatelessWidget {
  const _ObjectSectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseSectionTitle extends StatelessWidget {
  const _DatabaseSectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: colors.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, this.icon, this.borderRadius});

  final String label;
  final IconData? icon;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final surfaceStyle = NodeQlSurfaceStyle.of(context);
    final effectiveRadius = borderRadius ?? surfaceStyle.smallBorderRadius;
    return _clipDatabaseSurface(
      context: context,
      borderRadius: effectiveRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: effectiveRadius,
          border: Border.all(color: colors.secondary.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.onSecondaryContainer),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseValue extends StatelessWidget {
  const _DatabaseValue({required this.value, required this.catalog});

  final Object? value;
  final TranslationCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final text = _displayValue(value);
    final isNull = value == null;
    final isLong = text.length > 80 || text.contains('\n');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Tooltip(
        message: isLong ? catalog.text('databaseBrowser.openValue') : '',
        child: InkWell(
          onTap: isLong ? () => _showFullValue(context, text) : null,
          borderRadius: BorderRadius.circular(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: value is Uint8List ? 'monospace' : null,
                    fontStyle: isNull ? FontStyle.italic : null,
                    color: isNull
                        ? Theme.of(context).colorScheme.outline
                        : null,
                  ),
                ),
              ),
              if (isLong) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.open_in_full_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFullValue(BuildContext context, String text) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(catalog.text('databaseBrowser.value')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(catalog.text('common.close')),
          ),
        ],
      ),
    );
  }

  static String _displayValue(Object? value) {
    if (value == null) return 'NULL';
    if (value is Uint8List) {
      final hex = value
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      return "X'${hex.toUpperCase()}'";
    }
    return '$value';
  }
}
