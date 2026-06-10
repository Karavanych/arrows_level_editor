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
    this.startDirection,
  });

  final Color? paintColor;
  final bool isInactive;
  final bool hasStartMarker;
  final StartDirection? startDirection;

  EditorCell copyWith({
    Color? paintColor,
    bool clearPaintColor = false,
    bool? isInactive,
    bool? hasStartMarker,
    StartDirection? startDirection,
    bool clearStartDirection = false,
  }) {
    return EditorCell(
      paintColor: clearPaintColor ? null : (paintColor ?? this.paintColor),
      isInactive: isInactive ?? this.isInactive,
      hasStartMarker: hasStartMarker ?? this.hasStartMarker,
      startDirection: clearStartDirection
          ? null
          : (startDirection ?? this.startDirection),
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

enum EditorTool { paint, inactive, startMarker, erase }

enum BrushApplicationMode { point, line }

enum StartDirection { right, down, left, up }

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
        Color(0xFFD32F2F),
        Color(0xFFE53935),
        Color(0xFFF06292),
        Color(0xFFE91E63),
        Color(0xFFFB8C00),
        Color(0xFFFFB300),
        Color(0xFFFDD835),
        Color(0xFFFFEE58),
        Color(0xFF7CB342),
        Color(0xFF43A047),
        Color(0xFF00897B),
        Color(0xFF26A69A),
        Color(0xFF00ACC1),
        Color(0xFF039BE5),
        Color(0xFF1E88E5),
        Color(0xFF3949AB),
        Color(0xFF5E35B1),
        Color(0xFF8E24AA),
        Color(0xFF6D4C41),
        Color(0xFF8D6E63),
        Color(0xFF546E7A),
        Color(0xFF757575),
        Color(0xFF212121),
        Color(0xFFBDBDBD),
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
