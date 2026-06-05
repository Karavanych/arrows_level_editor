import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/persistence/model/alevelpack_models.dart';
import 'package:flutter/material.dart';

class EditorLevelMapper {
  const EditorLevelMapper();

  static const Color inactiveColor = Color(0xFFFFFFFF);

  ALevelPackLevel toPersistedLevel({
    required String levelId,
    required EditorState state,
  }) {
    final boardCells = <ALevelBoardCell>[];
    final startPoints = <ALevelStartPoint>[];
    final width = state.gridSize.width;

    for (var index = 0; index < state.cells.length; index += 1) {
      final cell = state.cells[index];
      final x = index % width;
      final y = index ~/ width;

      if (cell.hasStartMarker) {
        startPoints.add(ALevelStartPoint(x: x, y: y));
      }

      if (cell.isInactive) {
        boardCells.add(const ALevelBoardCell(isInactive: true));
        continue;
      }

      final color = cell.paintColor;
      if (color == null) {
        throw StateError(
          'Cannot save level "$levelId": empty cell found at ($x, $y).',
        );
      }

      boardCells.add(ALevelBoardCell(isInactive: false, color: color));
    }

    return ALevelPackLevel(
      id: levelId,
      width: state.gridSize.width,
      height: state.gridSize.height,
      boardCells: boardCells,
      meta: ALevelLevelMeta(startPoints: startPoints),
    );
  }

  EditorState fromPersistedLevel({
    required ALevelPackLevel level,
    required List<Color> paletteColors,
    Color selectedColor = Colors.red,
    EditorTool selectedTool = EditorTool.paint,
  }) {
    final cells = <EditorCell>[];
    for (final boardCell in level.boardCells) {
      if (boardCell.isInactive) {
        cells.add(const EditorCell(isInactive: true));
      } else {
        cells.add(EditorCell(paintColor: boardCell.color));
      }
    }

    for (final point in level.meta.startPoints) {
      final index = (point.y * level.width) + point.x;
      if (index < 0 || index >= cells.length) {
        continue;
      }
      final current = cells[index];
      cells[index] = current.copyWith(hasStartMarker: true);
    }

    return EditorState(
      gridSize: EditorGridSize(width: level.width, height: level.height),
      cells: cells,
      selectedColor: selectedColor,
      selectedTool: selectedTool,
      paletteColors: paletteColors,
    );
  }
}
