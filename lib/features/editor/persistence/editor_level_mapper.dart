import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/persistence/model/alevelpack_models.dart';
import 'package:flutter/material.dart';

class EditorLevelMapper {
  const EditorLevelMapper();

  static const Color inactiveColor = Color(0xFFFFFFFF);

  ALevelPackLevel toPersistedLevel({
    required String levelId,
    required EditorState state,
    bool checked = false,
  }) {
    final boardCells = <ALevelBoardCell>[];
    final startPoints = <ALevelStartPoint>[];
    final width = state.gridSize.width;

    for (var index = 0; index < state.cells.length; index += 1) {
      final cell = state.cells[index];
      final x = index % width;
      final y = index ~/ width;

      if (cell.hasStartMarker) {
        startPoints.add(
          ALevelStartPoint(
            x: x,
            y: y,
            direction: _toPersistedStartDirection(cell.startDirection),
          ),
        );
      }

      if (cell.isInactive) {
        boardCells.add(const ALevelBoardCell(isInactive: true));
        continue;
      }

      final color = cell.paintColor;
      if (color == null) {
        boardCells.add(const ALevelBoardCell(isInactive: false, isEmpty: true));
        continue;
      }

      boardCells.add(ALevelBoardCell(isInactive: false, color: color));
    }

    return ALevelPackLevel(
      id: levelId,
      width: state.gridSize.width,
      height: state.gridSize.height,
      boardCells: boardCells,
      meta: ALevelLevelMeta(startPoints: startPoints, checked: checked),
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
      if (boardCell.isEmpty) {
        cells.add(const EditorCell());
        continue;
      }
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
      cells[index] = current.copyWith(
        hasStartMarker: true,
        startDirection: _fromPersistedStartDirection(point.direction),
      );
    }

    return EditorState(
      gridSize: EditorGridSize(width: level.width, height: level.height),
      cells: cells,
      selectedColor: selectedColor,
      selectedTool: selectedTool,
      paletteColors: paletteColors,
    );
  }

  ALevelStartDirection _toPersistedStartDirection(StartDirection? direction) {
    switch (direction) {
      case StartDirection.down:
        return ALevelStartDirection.down;
      case StartDirection.left:
        return ALevelStartDirection.left;
      case StartDirection.up:
        return ALevelStartDirection.up;
      case StartDirection.right:
      case null:
        return ALevelStartDirection.right;
    }
  }

  StartDirection _fromPersistedStartDirection(ALevelStartDirection direction) {
    switch (direction) {
      case ALevelStartDirection.down:
        return StartDirection.down;
      case ALevelStartDirection.left:
        return StartDirection.left;
      case ALevelStartDirection.up:
        return StartDirection.up;
      case ALevelStartDirection.right:
        return StartDirection.right;
    }
  }
}
