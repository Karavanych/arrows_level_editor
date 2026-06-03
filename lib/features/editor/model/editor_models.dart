import 'package:flutter/material.dart';

class EditorGridSize {
  const EditorGridSize({required this.width, required this.height});

  final int width;
  final int height;
}

class EditorCell {
  const EditorCell({
    this.paintColor,
    this.isInactive = false,
    this.hasStartMarker = false,
  });

  final Color? paintColor;
  final bool isInactive;
  final bool hasStartMarker;

  EditorCell copyWith({
    Color? paintColor,
    bool clearPaintColor = false,
    bool? isInactive,
    bool? hasStartMarker,
  }) {
    return EditorCell(
      paintColor: clearPaintColor ? null : (paintColor ?? this.paintColor),
      isInactive: isInactive ?? this.isInactive,
      hasStartMarker: hasStartMarker ?? this.hasStartMarker,
    );
  }
}

class CellChange {
  const CellChange({
    required this.x,
    required this.y,
    required this.beforeCell,
    required this.afterCell,
  });

  final int x;
  final int y;
  final EditorCell beforeCell;
  final EditorCell afterCell;
}

class EditorStrokeChange {
  const EditorStrokeChange({required this.changes});

  final List<CellChange> changes;
}

enum EditorTool { paint, inactive, startMarker, erase, select }

class EditorState {
  const EditorState({
    required this.gridSize,
    required this.cells,
    required this.selectedColor,
    required this.selectedTool,
    required this.paletteColors,
    this.selectedCellIndex,
  });

  factory EditorState.initial({int width = 10, int height = 10}) {
    final gridSize = EditorGridSize(width: width, height: height);
    return EditorState(
      gridSize: gridSize,
      cells: List<EditorCell>.filled(width * height, const EditorCell()),
      selectedColor: Colors.red,
      selectedTool: EditorTool.paint,
      paletteColors: const [
        Colors.red,
        Colors.orange,
        Colors.yellow,
        Colors.green,
        Colors.blue,
        Colors.purple,
        Colors.cyan,
        Colors.brown,
        Colors.black,
        Color(0xFFE0E0E0),
      ],
    );
  }

  final EditorGridSize gridSize;
  final List<EditorCell> cells;
  final Color selectedColor;
  final EditorTool selectedTool;
  final List<Color> paletteColors;
  final int? selectedCellIndex;

  EditorState copyWith({
    EditorGridSize? gridSize,
    List<EditorCell>? cells,
    Color? selectedColor,
    EditorTool? selectedTool,
    List<Color>? paletteColors,
    int? selectedCellIndex,
    bool clearSelectedCell = false,
  }) {
    return EditorState(
      gridSize: gridSize ?? this.gridSize,
      cells: cells ?? this.cells,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedTool: selectedTool ?? this.selectedTool,
      paletteColors: paletteColors ?? this.paletteColors,
      selectedCellIndex: clearSelectedCell
          ? null
          : (selectedCellIndex ?? this.selectedCellIndex),
    );
  }
}
