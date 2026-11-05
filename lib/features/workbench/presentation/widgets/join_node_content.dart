import 'package:flutter/material.dart';
import 'package:nodeql/engine/block/block_node.dart';
import 'package:nodeql/engine/block/block_syntax.dart';
import 'package:nodeql/localization/generated/app_localizations.dart';

AppLocalizations joinStrings(String languageCode) {
  final locale = AppLocalizations.supportedLocales.firstWhere(
    (locale) => locale.languageCode == languageCode,
    orElse: () => const Locale('en'),
  );
  return lookupAppLocalizations(locale);
}

String joinOutcomeTitle(AppLocalizations strings, String kind) =>
    switch (kind) {
      'LEFT' => strings.joinKeepExisting,
      'RIGHT' => strings.joinKeepNew,
      'FULL' => strings.joinKeepAll,
      'CROSS' => strings.joinEveryPair,
      'NATURAL' => strings.joinSameNames,
      'SELF' => strings.joinSameTable,
      _ => strings.joinMatchesOnly,
    };

String joinOutcomeDescription(AppLocalizations strings, String kind) =>
    switch (kind) {
      'LEFT' => strings.joinLeftDescription,
      'RIGHT' => strings.joinRightDescription,
      'FULL' => strings.joinFullDescription,
      'CROSS' => strings.joinCrossDescription,
      'NATURAL' => strings.joinNaturalDescription,
      'SELF' => strings.joinSelfDescription,
      _ => strings.joinInnerDescription,
    };

/// A JOIN reads as a bridge between existing data and a new table. The slots
/// are supplied by the workbench, preserving its schema picker and reporters.
class JoinNodeContent extends StatelessWidget {
  const JoinNodeContent({
    required this.node,
    required this.sourceTable,
    required this.languageCode,
    required this.slotBuilder,
    this.onChooseKind,
    super.key,
  });

  static const width = 360.0;
  static const height = 88.0;

  final BlockNode node;
  final String? sourceTable;
  final String languageCode;
  final Widget Function(String inputKey, double width) slotBuilder;
  final VoidCallback? onChooseKind;

  @override
  Widget build(BuildContext context) {
    final strings = joinStrings(languageCode);
    final kind = joinTypeForNode(node);
    final rawCondition =
        node.inputs['imported_raw_on'] == true ||
        ('${node.inputs['on'] ?? ''}'.trim().isNotEmpty &&
            ('${node.inputs['left_column'] ?? ''}'.trim().isEmpty ||
                '${node.inputs['right_column'] ?? ''}'.trim().isEmpty));
    const white = TextStyle(color: Colors.white);
    return DefaultTextStyle.merge(
      style: white.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 10, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tableWidth = constraints.maxWidth * .31;
            final columnWidth = (constraints.maxWidth - 46) / 2;
            return Column(
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Tooltip(
                        message:
                            '${strings.joinConnectTables}\n${strings.joinExistingData}: ${sourceTable ?? strings.joinConnectSource}',
                        child: const Text('JOIN'),
                      ),
                      const SizedBox(width: 6),
                      slotBuilder('table', tableWidth),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message:
                              '${strings.joinResult} · $kind JOIN\n${joinOutcomeDescription(strings, kind)}',
                          child: Material(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              key: ValueKey('join-outcome-${node.id}'),
                              onTap: onChooseKind,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        joinOutcomeTitle(strings, kind),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: white.copyWith(fontSize: 11),
                                      ),
                                    ),
                                    if (onChooseKind != null)
                                      const Icon(
                                        Icons.expand_more_rounded,
                                        color: Colors.white,
                                        size: 14,
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
                const SizedBox(height: 4),
                SizedBox(
                  height: 32,
                  child: joinUsesCondition(node)
                      ? rawCondition
                            ? slotBuilder('on', constraints.maxWidth)
                            : Row(
                                children: [
                                  slotBuilder('left_column', columnWidth),
                                  const SizedBox(width: 6),
                                  slotBuilder('operator', 34),
                                  const SizedBox(width: 6),
                                  slotBuilder('right_column', columnWidth),
                                ],
                              )
                      : Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            joinOutcomeDescription(strings, kind),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: white.copyWith(fontSize: 11, height: 1.2),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Examples show rows rather than overlapping sets: outer joins retain
/// unmatched rows and fill the missing partner's cells with NULL.
class JoinKindDialog extends StatelessWidget {
  const JoinKindDialog({
    required this.selected,
    required this.languageCode,
    super.key,
  });

  final String selected;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final strings = joinStrings(languageCode);
    Widget option(String kind) {
      final isSelected = selected == kind;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('join-kind-$kind'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).pop(kind),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          joinOutcomeTitle(strings, kind),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          joinOutcomeDescription(strings, kind),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          kind == 'SELF' ? 'JOIN · AS' : '$kind JOIN',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (const [
                    'INNER',
                    'LEFT',
                    'RIGHT',
                    'FULL',
                  ].contains(kind)) ...[
                    const SizedBox(width: 12),
                    JoinRowExample(kind: kind),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(strings.joinChooseResult),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.joinExampleHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final kind in ['INNER', 'LEFT', 'RIGHT', 'FULL'])
                option(kind),
              Text(
                strings.joinNullHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                initiallyExpanded: const [
                  'CROSS',
                  'NATURAL',
                  'SELF',
                ].contains(selected),
                tilePadding: EdgeInsets.zero,
                title: Text(strings.joinSpecialCases),
                children: [
                  for (final kind in ['CROSS', 'NATURAL', 'SELF']) option(kind),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.joinClose),
        ),
      ],
    );
  }
}

class JoinRowExample extends StatelessWidget {
  const JoinRowExample({required this.kind, super.key});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    Widget row(String left, String right) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in [left, right])
            Container(
              width: 42,
              margin: const EdgeInsetsDirectional.only(start: 3),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: foreground.withValues(
                  alpha: value == 'NULL' ? .04 : .12,
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: foreground.withValues(alpha: .2)),
              ),
              alignment: Alignment.center,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('1', '1'),
          if (kind == 'LEFT' || kind == 'FULL') row('2', 'NULL'),
          if (kind == 'RIGHT' || kind == 'FULL') row('NULL', '3'),
        ],
      ),
    );
  }
}
