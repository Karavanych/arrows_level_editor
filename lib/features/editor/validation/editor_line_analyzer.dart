import 'dart:collection';

import 'package:arrows_level_editor/features/editor/model/editor_models.dart';

class ColorConnectedComponent {
  const ColorConnectedComponent({
    required this.id,
    required this.colorArgb,
    required this.cellIndices,
  });

  final int id;
  final int colorArgb;
  final List<int> cellIndices;
}

class EditorLineAnalyzer {
  const EditorLineAnalyzer();

  List<ColorConnectedComponent> findColorConnectedComponents(
    EditorState state,
  ) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    final visited = <int>{};
    final components = <ColorConnectedComponent>[];
    var nextComponentId = 1;

    for (var index = 0; index < state.cells.length; index += 1) {
      if (visited.contains(index)) {
        continue;
      }
      final colorArgb = _cellColorArgb(state.cells[index]);
      if (colorArgb == null) {
        continue;
      }

      final componentIndices = <int>[];
      final queue = Queue<int>()..add(index);
      visited.add(index);

      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        componentIndices.add(current);

        for (final neighbor in _neighbors4(
          current,
          width: width,
          height: height,
        )) {
          if (visited.contains(neighbor)) {
            continue;
          }
          if (_cellColorArgb(state.cells[neighbor]) != colorArgb) {
            continue;
          }
          visited.add(neighbor);
          queue.add(neighbor);
        }
      }

      components.add(
        ColorConnectedComponent(
          id: nextComponentId,
          colorArgb: colorArgb,
          cellIndices: componentIndices,
        ),
      );
      nextComponentId += 1;
    }

    return components;
  }

  bool componentHasStartMarker(
    EditorState state,
    ColorConnectedComponent component,
  ) {
    for (final index in component.cellIndices) {
      if (state.cells[index].hasStartMarker) {
        return true;
      }
    }
    return false;
  }

  int? findTemporaryStartCandidate(
    EditorState state,
    ColorConnectedComponent component,
  ) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;

    for (final index in component.cellIndices) {
      final neighborsCount = _sameColorNeighborCount(
        state,
        index: index,
        colorArgb: component.colorArgb,
        width: width,
        height: height,
      );
      if (neighborsCount == 1) {
        return index;
      }
    }
    return null;
  }

  int _sameColorNeighborCount(
    EditorState state, {
    required int index,
    required int colorArgb,
    required int width,
    required int height,
  }) {
    var count = 0;
    for (final neighbor in _neighbors4(index, width: width, height: height)) {
      if (_cellColorArgb(state.cells[neighbor]) == colorArgb) {
        count += 1;
      }
    }
    return count;
  }

  Iterable<int> _neighbors4(
    int index, {
    required int width,
    required int height,
  }) sync* {
    final x = index % width;
    final y = index ~/ width;

    if (x > 0) {
      yield index - 1;
    }
    if (x < width - 1) {
      yield index + 1;
    }
    if (y > 0) {
      yield index - width;
    }
    if (y < height - 1) {
      yield index + width;
    }
  }

  int? _cellColorArgb(EditorCell cell) {
    if (cell.isInactive) {
      return null;
    }
    final color = cell.paintColor;
    if (color == null) {
      return null;
    }
    return color.toARGB32();
  }
}
