import 'dart:ui';

import 'package:scratchql_creater/engine/workspace/workspace_models.dart';

class WorkspaceDockingService {
  const WorkspaceDockingService({this.magneticDistance = 18});

  final double magneticDistance;

  DockingResult evaluate({required Offset source, required Offset target}) {
    final delta = target - source;
    final shouldSnap = delta.distance <= magneticDistance;
    return DockingResult(
      shouldSnap: shouldSnap,
      snapOffset: shouldSnap ? delta : Offset.zero,
    );
  }
}
