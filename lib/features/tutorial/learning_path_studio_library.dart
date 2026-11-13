import 'package:flutter/material.dart';
import 'package:nodeql/features/tutorial/learning_path_authoring.dart';
import 'package:nodeql/features/tutorial/learning_path_review.dart';
import 'package:nodeql/localization/translation_catalog.dart';

enum _WorkshopFilter { all, drafts, official }

enum _WorkshopSort { library, title, steps }

class LearningPathStudioLibrary extends StatefulWidget {
  const LearningPathStudioLibrary({
    required this.catalog,
    required this.paths,
    required this.onCreate,
    required this.onEdit,
    required this.onPreview,
    required this.onDuplicate,
    this.draftIds,
    this.busy = false,
    this.reviewFor,
    this.onImport,
    this.onExportCatalog,
    this.onCheck,
    this.onShareClassroom,
    this.onExportDownload,
    this.onDelete,
    super.key,
  });

  final TranslationCatalog catalog;
  final List<AuthoredLearningPath> paths;

  /// With no draft IDs supplied, all paths are treated as editable.
  final Set<String>? draftIds;
  final bool busy;
  final LearningPathReview Function(AuthoredLearningPath)? reviewFor;
  final VoidCallback onCreate;
  final VoidCallback? onImport;
  final VoidCallback? onExportCatalog;
  final ValueChanged<AuthoredLearningPath> onEdit;
  final ValueChanged<AuthoredLearningPath> onPreview;
  final ValueChanged<AuthoredLearningPath> onDuplicate;
  final ValueChanged<AuthoredLearningPath>? onCheck;
  final ValueChanged<AuthoredLearningPath>? onShareClassroom;
  final ValueChanged<AuthoredLearningPath>? onExportDownload;
  final Future<void> Function(AuthoredLearningPath)? onDelete;

  @override
  State<LearningPathStudioLibrary> createState() =>
      _LearningPathStudioLibraryState();
}

class _LearningPathStudioLibraryState extends State<LearningPathStudioLibrary> {
  final _search = TextEditingController();
  _WorkshopFilter _filter = _WorkshopFilter.all;
  _WorkshopSort _sort = _WorkshopSort.library;

  TranslationCatalog get _catalog => widget.catalog;

  String _text(String key) => _catalog.text('tutorial.studio.$key');

  bool _isDraft(AuthoredLearningPath path) =>
      widget.draftIds?.contains(path.id) ?? true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AuthoredLearningPath> _visiblePaths() {
    final query = _search.text.trim().toLowerCase();
    final terms = query.isEmpty
        ? const <String>[]
        : query.split(RegExp(r'\s+'));
    final visible = widget.paths.where((path) {
      final included = switch (_filter) {
        _WorkshopFilter.all => true,
        _WorkshopFilter.drafts => _isDraft(path),
        _WorkshopFilter.official => !_isDraft(path),
      };
      if (!included || terms.isEmpty) {
        return included;
      }
      final searchable = [
        path.titleFor(_catalog.locale),
        path.descriptionFor(_catalog.locale),
        for (final step in path.steps) step.title,
      ].join(' ').toLowerCase();
      return terms.every(searchable.contains);
    }).toList();

    if (_sort != _WorkshopSort.library) {
      visible.sort((first, second) {
        if (_sort == _WorkshopSort.steps) {
          final bySteps = second.steps.length.compareTo(first.steps.length);
          if (bySteps != 0) return bySteps;
        }
        final byTitle = first
            .titleFor(_catalog.locale)
            .toLowerCase()
            .compareTo(second.titleFor(_catalog.locale).toLowerCase());
        return byTitle != 0 ? byTitle : first.id.compareTo(second.id);
      });
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePaths();
    final total = widget.paths.length;
    final drafts = widget.paths.where(_isDraft).length;
    return FocusTraversalGroup(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context)),
          if (widget.busy)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (total > 0)
            SliverToBoxAdapter(child: _buildFilters(total, drafts)),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(context, hasPaths: total > 0),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.separated(
                itemCount: visible.length,
                itemBuilder: (context, index) =>
                    _buildCard(context, visible[index]),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(_text('title'), style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 4),
          Text(_text('subtitle'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                key: const ValueKey('learning-path-create'),
                onPressed: widget.busy ? null : widget.onCreate,
                icon: const Icon(Icons.add),
                label: Text(_text('create')),
              ),
              if (widget.onImport != null)
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.onImport,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(_text('import')),
                ),
              if (widget.onExportCatalog != null && widget.paths.isNotEmpty)
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.onExportCatalog,
                  icon: const Icon(Icons.ios_share_outlined),
                  label: Text(_text('export')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(int total, int drafts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('learning-path-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _text('search'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(_search.clear),
                            tooltip: _text('clearSearch'),
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_WorkshopSort>(
                tooltip: _text('sort'),
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (sort) => setState(() => _sort = sort),
                itemBuilder: (_) => [
                  for (final (sort, label) in [
                    (_WorkshopSort.library, 'sortLibrary'),
                    (_WorkshopSort.title, 'sortTitle'),
                    (_WorkshopSort.steps, 'sortSteps'),
                  ])
                    CheckedPopupMenuItem(
                      value: sort,
                      checked: sort == _sort,
                      child: Text(_text(label)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final (filter, key, count) in [
                (_WorkshopFilter.all, 'filterAll', total),
                (_WorkshopFilter.drafts, 'filterDrafts', drafts),
                (_WorkshopFilter.official, 'filterOfficial', total - drafts),
              ])
                ChoiceChip(
                  label: Text(
                    _catalog.text('tutorial.studio.$key', {'count': count}),
                  ),
                  selected: _filter == filter,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, {required bool hasPaths}) {
    final style = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasPaths ? Icons.search_off : Icons.route_outlined, size: 36),
            const SizedBox(height: 10),
            Text(
              _text(hasPaths ? 'noMatches' : 'emptyTitle'),
              style: style.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            if (hasPaths)
              TextButton(
                onPressed: () => setState(() {
                  _search.clear();
                  _filter = _WorkshopFilter.all;
                }),
                child: Text(_text('resetFilters')),
              )
            else
              Text(_text('emptyBody'), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, AuthoredLearningPath path) {
    final title = path.titleFor(_catalog.locale);
    final description = path.descriptionFor(_catalog.locale);
    final draft = _isDraft(path);
    final review = widget.reviewFor?.call(path);
    final textTheme = Theme.of(context).textTheme;
    final onCheck = widget.onCheck;
    final onShareClassroom = widget.onShareClassroom;
    final onExportDownload = widget.onExportDownload;
    final hasMenu =
        draft ||
        onExportDownload != null ||
        (onCheck != null && review == null);

    return Card.outlined(
      key: ValueKey('learning-path-card-${path.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: textTheme.titleMedium)),
                if (hasMenu)
                  PopupMenuButton<VoidCallback>(
                    key: ValueKey('learning-path-actions-${path.id}'),
                    enabled: !widget.busy,
                    tooltip: _text('moreActions'),
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      if (onCheck != null && review == null)
                        PopupMenuItem(
                          value: () => onCheck(path),
                          child: Text(_text('checkWorkshop')),
                        ),
                      if (draft)
                        PopupMenuItem(
                          value: () => widget.onDuplicate(path),
                          child: Text(_text('duplicate')),
                        ),
                      if (onExportDownload != null)
                        PopupMenuItem(
                          value: () => onExportDownload(path),
                          child: Text(
                            _catalog.text('tutorial.download.export'),
                          ),
                        ),
                      if (draft && widget.onDelete != null)
                        PopupMenuItem(
                          value: () => _confirmDelete(path),
                          child: Text(_text('delete')),
                        ),
                    ],
                  ),
              ],
            ),
            if (description.isNotEmpty)
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  _text(draft ? 'draftBadge' : 'officialBadge'),
                  style: textTheme.labelMedium,
                ),
                Text(
                  '${path.steps.length} ${_text('steps')}',
                  style: textTheme.bodySmall,
                ),
                if (path.calloutCount > 0)
                  Text(
                    '${path.calloutCount} ${_text('callouts')}',
                    style: textTheme.bodySmall,
                  ),
              ],
            ),
            if (review != null) ...[
              const SizedBox(height: 4),
              _buildReviewStatus(
                review,
                onCheck == null ? null : () => onCheck(path),
              ),
            ],
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                FilledButton.tonalIcon(
                  onPressed: widget.busy
                      ? null
                      : draft
                      ? () => widget.onEdit(path)
                      : () => widget.onDuplicate(path),
                  icon: Icon(draft ? Icons.edit_outlined : Icons.copy_outlined),
                  label: Text(_text(draft ? 'edit' : 'duplicate')),
                ),
                TextButton.icon(
                  onPressed: widget.busy ? null : () => widget.onPreview(path),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_text('start')),
                ),
                if (onShareClassroom != null)
                  TextButton.icon(
                    onPressed: widget.busy
                        ? null
                        : () => onShareClassroom(path),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(_catalog.text('tutorial.classroom.share')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStatus(LearningPathReview review, VoidCallback? onCheck) {
    final icon = Icon(
      review.canShare ? Icons.check_circle_outline : Icons.info_outline,
      size: 18,
    );
    final label = Text(_text(review.canShare ? 'readyToShare' : 'needsReview'));
    return onCheck == null
        ? Chip(avatar: icon, label: label)
        : ActionChip(
            avatar: icon,
            label: label,
            tooltip: _text('checkWorkshop'),
            onPressed: widget.busy ? null : onCheck,
          );
  }

  Future<void> _confirmDelete(AuthoredLearningPath path) async {
    final title = path.titleFor(_catalog.locale);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('deleteTitle')),
        content: Text(
          _catalog.text('tutorial.studio.deleteBody', {'title': title}),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_text('deleteConfirm')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || widget.busy || !_isDraft(path)) return;
    await widget.onDelete?.call(path);
  }
}
