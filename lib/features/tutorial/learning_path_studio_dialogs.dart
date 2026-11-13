part of 'learning_path_studio.dart';

void _showStudioMessage(
  BuildContext context,
  TranslationCatalog catalog,
  String key, [
  Map<String, Object?> values = const {},
]) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(catalog.text('tutorial.studio.$key', values))),
  );
}

Future<bool> _confirmDiscard(
  BuildContext context,
  TranslationCatalog catalog,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(catalog.text('tutorial.studio.unsavedTitle')),
          content: Text(catalog.text('tutorial.studio.unsavedBody')),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(catalog.text('tutorial.studio.returnToEditor')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(catalog.text('tutorial.studio.discard')),
            ),
          ],
        ),
      ) ??
      false;
}

Future<int?> _showWorkshopReview(
  BuildContext context,
  TranslationCatalog catalog,
  AuthoredLearningPath path,
  LearningPathReview review, {
  bool canEditSteps = false,
}) => showDialog<int>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(catalog.text('tutorial.studio.checkWorkshop')),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (path.title.trim().isNotEmpty) ...[
              Text(
                path.titleFor(catalog.locale),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
            ],
            _StudioNotice(
              icon: review.canShare
                  ? Icons.check_circle_outline
                  : Icons.fact_check_outlined,
              text: catalog.text(
                review.canShare
                    ? 'tutorial.studio.review.ready'
                    : review.canPreview
                    ? 'tutorial.studio.review.previewOnly'
                    : 'tutorial.studio.review.blocked',
              ),
            ),
            for (final issue in review.issues) ...[
              const SizedBox(height: 8),
              _buildReviewIssue(context, catalog, path, issue, canEditSteps),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).closeButtonLabel),
      ),
    ],
  ),
);

Widget _buildReviewIssue(
  BuildContext context,
  TranslationCatalog catalog,
  AuthoredLearningPath path,
  LearningPathReviewIssue issue,
  bool canEditSteps,
) {
  final distributionProblem = issue.distributionProblem;
  final key = distributionProblem == null
      ? 'tutorial.studio.review.${issue.code.name}'
      : 'tutorial.studio.distribution.${distributionProblem.name}';
  final index = issue.stepIndex;
  final step = index == null || index < 0 || index >= path.steps.length
      ? null
      : path.steps[index];
  final canEdit = canEditSteps && step != null;
  final detail = issue.detail;
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      issue.blocksPreview ? Icons.error_outline : Icons.info_outline,
    ),
    title: Text(catalog.text(key)),
    subtitle: step == null && (detail == null || detail.isEmpty)
        ? null
        : Text(
            [
              if (step != null)
                '${catalog.text('tutorial.studio.stepEditor', {'number': index! + 1})}'
                    '${step.title.isEmpty ? '' : ' · ${step.title}'}',
              if (detail != null && detail.isNotEmpty) detail,
            ].join('\n'),
          ),
    trailing: canEdit ? const Icon(Icons.edit_outlined) : null,
    onTap: canEdit ? () => Navigator.pop(context, index) : null,
  );
}

Future<bool> _confirmWorkshopImport(
  BuildContext context,
  TranslationCatalog catalog,
  List<AuthoredLearningPath> paths,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(catalog.text('tutorial.studio.importPreview')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    catalog.text('tutorial.studio.importBody', {
                      'count': paths.length,
                    }),
                  ),
                  const SizedBox(height: 8),
                  for (final path in paths.take(12))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(path.titleFor(catalog.locale)),
                      subtitle: Text(
                        '${path.steps.length} ${catalog.text('tutorial.studio.steps')}',
                      ),
                    ),
                  if (paths.length > 12)
                    Text(
                      catalog.text('tutorial.studio.importMore', {
                        'count': paths.length - 12,
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(catalog.text('tutorial.studio.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(catalog.text('tutorial.studio.importConfirm')),
            ),
          ],
        ),
      ) ??
      false;
}

Future<List<AuthoredLearningPath>?> _selectCatalogPaths(
  BuildContext context,
  TranslationCatalog catalog,
  List<AuthoredLearningPath> paths,
  LearningPathReview Function(AuthoredLearningPath) review,
) {
  final eligible = {
    for (final path in paths)
      if (review(path).canExportCatalog) path,
  };
  final selected = {...eligible};
  return showDialog<List<AuthoredLearningPath>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(catalog.text('tutorial.studio.export')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(catalog.text('tutorial.studio.catalogBody')),
                if (eligible.length != paths.length) ...[
                  const SizedBox(height: 8),
                  Text(catalog.text('tutorial.studio.catalogBlocked')),
                ],
                const SizedBox(height: 8),
                for (final path in paths)
                  CheckboxListTile(
                    key: ValueKey('catalog-${path.id}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(path.titleFor(catalog.locale)),
                    value: selected.contains(path),
                    onChanged: !eligible.contains(path)
                        ? null
                        : (checked) => setState(() {
                            if (checked == true) {
                              selected.add(path);
                            } else {
                              selected.remove(path);
                            }
                          }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: Text(catalog.text('tutorial.studio.cancel')),
          ),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    paths.where(selected.contains).toList(),
                  ),
            child: Text(catalog.text('tutorial.studio.catalogConfirm')),
          ),
        ],
      ),
    ),
  );
}
