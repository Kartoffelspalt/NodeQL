import 'package:flutter/material.dart';

/// Topic icons shared by the official workshop cards and their player.
/// Stable IDs keep the icon independent of the displayed language.
IconData workshopIconFor(String workshopId) => switch (workshopId) {
  'nodeql-overview' => Icons.dashboard_outlined,
  'nodeql-nodes-and-values' => Icons.account_tree_outlined,
  'nodeql-workshop-tools' => Icons.construction_outlined,
  'sqlite-select-and-filters' => Icons.filter_alt_outlined,
  'sqlite-data-types' => Icons.data_object_outlined,
  'sqlite-advanced-filters' => Icons.filter_list_alt,
  'sqlite-sorting-and-where' => Icons.sort_by_alpha_outlined,
  'sqlite-complex-queries' => Icons.hub_outlined,
  'sqlite-data-manipulation' => Icons.edit_note_outlined,
  'sqlite-schema-objects' => Icons.schema_outlined,
  'sqlite-transactions' => Icons.restore_outlined,
  _ => Icons.timeline_rounded,
};
