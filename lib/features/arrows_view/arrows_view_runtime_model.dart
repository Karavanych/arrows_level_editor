import 'dart:ui';

class ArrowsViewRuntimeModel {
  const ArrowsViewRuntimeModel({
    required this.levelId,
    required this.width,
    required this.height,
    required this.activeMask,
    required this.colorByCell,
    required this.paths,
  });

  final String levelId;
  final int width;
  final int height;
  final List<bool> activeMask;
  final List<int?> colorByCell;
  final List<ArrowsViewRenderPath> paths;

  Iterable<Offset> get supportPoints sync* {
    for (var index = 0; index < activeMask.length; index += 1) {
      if (!activeMask[index]) {
        continue;
      }
      yield Offset((index % width).toDouble(), (index ~/ width).toDouble());
    }
  }
}

class ArrowsViewRenderPath {
  const ArrowsViewRenderPath({
    required this.colorValue,
    required this.cellIndices,
    required this.points,
    required this.headPose,
  });

  final int colorValue;
  final List<int> cellIndices; // tail -> head (head is the last entry)
  final List<Offset> points; // logical grid coordinates, tail -> head
  final ArrowsViewHeadPose headPose;

  int get segmentCount => points.length - 1;
}

class ArrowsViewHeadPose {
  const ArrowsViewHeadPose({required this.position, required this.direction});

  final Offset position;
  final Offset direction; // normalized logical direction
}

class ArrowsViewRuntimeBuildException implements Exception {
  const ArrowsViewRuntimeBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}
