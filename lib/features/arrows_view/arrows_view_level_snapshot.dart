import 'package:arrows_level_editor/features/editor/model/editor_models.dart';

class ArrowsViewLevelSnapshot {
  const ArrowsViewLevelSnapshot({
    required this.levelId,
    required this.gridWidth,
    required this.gridHeight,
    required this.cells,
    required this.startPoints,
    required this.paletteColors,
    required this.selectedTool,
  });

  factory ArrowsViewLevelSnapshot.fromEditorState({
    required String levelId,
    required EditorState state,
  }) {
    final width = state.gridSize.width;
    final cells = List<ArrowsViewCellSnapshot>.generate(state.cells.length, (
      index,
    ) {
      final cell = state.cells[index];
      final x = index % width;
      final y = index ~/ width;
      return ArrowsViewCellSnapshot(
        index: index,
        x: x,
        y: y,
        paintColorValue: cell.paintColor?.toARGB32(),
        isInactive: cell.isInactive,
        hasStartMarker: cell.hasStartMarker,
        startDirection: _startDirectionToString(cell.startDirection),
      );
    });
    final starts = cells
        .where((cell) => cell.hasStartMarker)
        .map((cell) {
          return ArrowsViewStartPointSnapshot(
            x: cell.x,
            y: cell.y,
            direction: cell.startDirection,
          );
        })
        .toList(growable: false);

    return ArrowsViewLevelSnapshot(
      levelId: levelId,
      gridWidth: width,
      gridHeight: state.gridSize.height,
      cells: cells,
      startPoints: starts,
      paletteColors: state.paletteColors
          .map((color) => color.toARGB32())
          .toList(growable: false),
      selectedTool: state.selectedTool.name,
    );
  }

  factory ArrowsViewLevelSnapshot.fromJson(Map<String, dynamic> json) {
    return ArrowsViewLevelSnapshot(
      levelId: (json['levelId'] as String?) ?? 'unknown',
      gridWidth: (json['gridWidth'] as num?)?.toInt() ?? 0,
      gridHeight: (json['gridHeight'] as num?)?.toInt() ?? 0,
      cells: ((json['cells'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ArrowsViewCellSnapshot.fromJson)
          .toList(growable: false),
      startPoints:
          ((json['startPoints'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(ArrowsViewStartPointSnapshot.fromJson)
              .toList(growable: false),
      paletteColors:
          ((json['paletteColors'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false),
      selectedTool: (json['selectedTool'] as String?) ?? 'paint',
    );
  }

  final String levelId;
  final int gridWidth;
  final int gridHeight;
  final List<ArrowsViewCellSnapshot> cells;
  final List<ArrowsViewStartPointSnapshot> startPoints;
  final List<int> paletteColors;
  final String selectedTool;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'levelId': levelId,
      'gridWidth': gridWidth,
      'gridHeight': gridHeight,
      'cells': cells.map((cell) => cell.toJson()).toList(growable: false),
      'startPoints': startPoints
          .map((startPoint) => startPoint.toJson())
          .toList(growable: false),
      'paletteColors': paletteColors,
      'selectedTool': selectedTool,
    };
  }
}

class ArrowsViewCellSnapshot {
  const ArrowsViewCellSnapshot({
    required this.index,
    required this.x,
    required this.y,
    required this.paintColorValue,
    required this.isInactive,
    required this.hasStartMarker,
    required this.startDirection,
  });

  factory ArrowsViewCellSnapshot.fromJson(Map<String, dynamic> json) {
    return ArrowsViewCellSnapshot(
      index: (json['index'] as num?)?.toInt() ?? 0,
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      paintColorValue: (json['paintColorValue'] as num?)?.toInt(),
      isInactive: (json['isInactive'] as bool?) ?? false,
      hasStartMarker: (json['hasStartMarker'] as bool?) ?? false,
      startDirection: json['startDirection'] as String?,
    );
  }

  final int index;
  final int x;
  final int y;
  final int? paintColorValue;
  final bool isInactive;
  final bool hasStartMarker;
  final String? startDirection;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'index': index,
      'x': x,
      'y': y,
      'paintColorValue': paintColorValue,
      'isInactive': isInactive,
      'hasStartMarker': hasStartMarker,
      'startDirection': startDirection,
    };
  }
}

class ArrowsViewStartPointSnapshot {
  const ArrowsViewStartPointSnapshot({
    required this.x,
    required this.y,
    required this.direction,
  });

  factory ArrowsViewStartPointSnapshot.fromJson(Map<String, dynamic> json) {
    return ArrowsViewStartPointSnapshot(
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      direction: json['direction'] as String?,
    );
  }

  final int x;
  final int y;
  final String? direction;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'x': x, 'y': y, 'direction': direction};
  }
}

String? _startDirectionToString(StartDirection? direction) {
  if (direction == null) {
    return null;
  }
  return direction.name;
}
