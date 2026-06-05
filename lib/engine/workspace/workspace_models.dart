import 'dart:ui';

class WorkspaceTransform {
  const WorkspaceTransform({required this.zoom, required this.pan});

  final double zoom;
  final Offset pan;

  WorkspaceTransform copyWith({double? zoom, Offset? pan}) => WorkspaceTransform(
        zoom: zoom ?? this.zoom,
        pan: pan ?? this.pan,
      );
}

class DockingResult {
  const DockingResult({required this.shouldSnap, this.snapOffset = Offset.zero});

  final bool shouldSnap;
  final Offset snapOffset;
}
