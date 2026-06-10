import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_line_analyzer.dart';

enum SaveValidationProblemCode {
  emptyCells,
  singleCellColorIsland,
  missingLineStart,
}

enum SaveValidationAutoFixType { fillEmptyCellsAsInactive, addTemporaryStarts }

class SaveValidationProblem {
  const SaveValidationProblem({
    required this.code,
    required this.message,
    required this.isBlocking,
    required this.cellIndices,
    this.componentId,
  });

  final SaveValidationProblemCode code;
  final String message;
  final bool isBlocking;
  final List<int> cellIndices;
  final int? componentId;
}

class SaveValidationAutoFix {
  const SaveValidationAutoFix({
    required this.type,
    required this.label,
    required this.cellIndices,
    this.startCandidatesByComponentId = const {},
  });

  final SaveValidationAutoFixType type;
  final String label;
  final List<int> cellIndices;
  final Map<int, int> startCandidatesByComponentId;
}

class SaveValidationResult {
  const SaveValidationResult({required this.problems, required this.autoFixes});

  final List<SaveValidationProblem> problems;
  final List<SaveValidationAutoFix> autoFixes;

  bool get hasBlockingProblems => problems.any((problem) => problem.isBlocking);
}

class EditorSaveValidationService {
  EditorSaveValidationService({EditorLineAnalyzer? lineAnalyzer})
    : _lineAnalyzer = lineAnalyzer ?? const EditorLineAnalyzer();

  final EditorLineAnalyzer _lineAnalyzer;

  SaveValidationResult validate(EditorState state) {
    final problems = <SaveValidationProblem>[];
    final autoFixes = <SaveValidationAutoFix>[];

    final emptyCellIndices = _findEmptyCells(state);
    if (emptyCellIndices.isNotEmpty) {
      problems.add(
        SaveValidationProblem(
          code: SaveValidationProblemCode.emptyCells,
          message: 'Level contains empty cells.',
          isBlocking: true,
          cellIndices: emptyCellIndices,
        ),
      );
      autoFixes.add(
        SaveValidationAutoFix(
          type: SaveValidationAutoFixType.fillEmptyCellsAsInactive,
          label: 'Fill all empty cells as inactive',
          cellIndices: emptyCellIndices,
        ),
      );
    }

    final components = _lineAnalyzer.findColorConnectedComponents(state);
    final temporaryStartCandidatesByComponent = <int, int>{};
    for (final component in components) {
      if (component.cellIndices.length == 1) {
        problems.add(
          SaveValidationProblem(
            code: SaveValidationProblemCode.singleCellColorIsland,
            message: 'Single-cell color island is not allowed.',
            isBlocking: true,
            cellIndices: component.cellIndices,
            componentId: component.id,
          ),
        );
      }

      if (_componentHasCompleteStart(state, component)) {
        continue;
      }

      problems.add(
        SaveValidationProblem(
          code: SaveValidationProblemCode.missingLineStart,
          message: 'Color-connected line has no start marker.',
          isBlocking: true,
          cellIndices: component.cellIndices,
          componentId: component.id,
        ),
      );

      final candidate = _lineAnalyzer.findTemporaryStartCandidate(
        state,
        component,
      );
      if (candidate != null) {
        temporaryStartCandidatesByComponent[component.id] = candidate;
      }
    }

    if (temporaryStartCandidatesByComponent.isNotEmpty) {
      autoFixes.add(
        SaveValidationAutoFix(
          type: SaveValidationAutoFixType.addTemporaryStarts,
          label: 'Add temporary starts for lines without starts',
          cellIndices: temporaryStartCandidatesByComponent.values.toList(),
          startCandidatesByComponentId: temporaryStartCandidatesByComponent,
        ),
      );
    }

    return SaveValidationResult(problems: problems, autoFixes: autoFixes);
  }

  EditorState applyAutoFix({
    required EditorState state,
    required SaveValidationAutoFixType autoFixType,
  }) {
    switch (autoFixType) {
      case SaveValidationAutoFixType.fillEmptyCellsAsInactive:
        return _fillEmptyCellsAsInactive(state);
      case SaveValidationAutoFixType.addTemporaryStarts:
        return _addTemporaryStarts(state);
    }
  }

  EditorState _fillEmptyCellsAsInactive(EditorState state) {
    final nextCells = List<EditorCell>.from(state.cells);
    for (var index = 0; index < nextCells.length; index += 1) {
      final cell = nextCells[index];
      if (cell.paintColor == null && !cell.isInactive) {
        nextCells[index] = const EditorCell(isInactive: true);
      }
    }
    return state.copyWith(cells: nextCells, clearSelectedCell: true);
  }

  EditorState _addTemporaryStarts(EditorState state) {
    final components = _lineAnalyzer.findColorConnectedComponents(state);
    final nextCells = List<EditorCell>.from(state.cells);

    for (final component in components) {
      final completeStart = _findCompleteStartIndex(state, component);
      if (completeStart != null) {
        continue;
      }

      final existingMarkerIndex = _findAnyStartMarkerIndex(state, component);
      if (existingMarkerIndex != null) {
        final existing = nextCells[existingMarkerIndex];
        final validDirections = _validStartDirectionsForCell(
          state: state,
          cellIndex: existingMarkerIndex,
          colorArgb: component.colorArgb,
        );
        if (validDirections.isNotEmpty) {
          nextCells[existingMarkerIndex] = existing.copyWith(
            hasStartMarker: true,
            startDirection: validDirections.first,
          );
        }
        continue;
      }
      final candidate = _lineAnalyzer.findTemporaryStartCandidate(
        state,
        component,
      );
      if (candidate == null) {
        continue;
      }
      final current = nextCells[candidate];
      final validDirections = _validStartDirectionsForCell(
        state: state,
        cellIndex: candidate,
        colorArgb: component.colorArgb,
      );
      if (validDirections.isEmpty) {
        continue;
      }
      nextCells[candidate] = current.copyWith(
        hasStartMarker: true,
        startDirection: validDirections.first,
      );
    }

    return state.copyWith(cells: nextCells, clearSelectedCell: true);
  }

  bool _componentHasCompleteStart(
    EditorState state,
    ColorConnectedComponent component,
  ) {
    return _findCompleteStartIndex(state, component) != null;
  }

  int? _findCompleteStartIndex(
    EditorState state,
    ColorConnectedComponent component,
  ) {
    for (final index in component.cellIndices) {
      final cell = state.cells[index];
      if (!cell.hasStartMarker || cell.startDirection == null) {
        continue;
      }
      final validDirections = _validStartDirectionsForCell(
        state: state,
        cellIndex: index,
        colorArgb: component.colorArgb,
      );
      if (validDirections.contains(cell.startDirection)) {
        return index;
      }
    }
    return null;
  }

  int? _findAnyStartMarkerIndex(
    EditorState state,
    ColorConnectedComponent component,
  ) {
    for (final index in component.cellIndices) {
      if (state.cells[index].hasStartMarker) {
        return index;
      }
    }
    return null;
  }

  List<StartDirection> _validStartDirectionsForCell({
    required EditorState state,
    required int cellIndex,
    required int colorArgb,
  }) {
    final valid = <StartDirection>[];
    for (final direction in StartDirection.values) {
      final behindIndex = _behindNeighborIndex(
        state: state,
        cellIndex: cellIndex,
        direction: direction,
      );
      if (behindIndex == null) {
        continue;
      }
      final behindCell = state.cells[behindIndex];
      if (!behindCell.isInactive &&
          behindCell.paintColor?.toARGB32() == colorArgb) {
        valid.add(direction);
      }
    }
    return valid;
  }

  int? _behindNeighborIndex({
    required EditorState state,
    required int cellIndex,
    required StartDirection direction,
  }) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    final x = cellIndex % width;
    final y = cellIndex ~/ width;
    final (dx, dy) = switch (direction) {
      StartDirection.right => (-1, 0),
      StartDirection.down => (0, -1),
      StartDirection.left => (1, 0),
      StartDirection.up => (0, 1),
    };
    final nx = x + dx;
    final ny = y + dy;
    if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
      return null;
    }
    return ny * width + nx;
  }

  List<int> _findEmptyCells(EditorState state) {
    final result = <int>[];
    for (var index = 0; index < state.cells.length; index += 1) {
      final cell = state.cells[index];
      if (cell.paintColor == null && !cell.isInactive) {
        result.add(index);
      }
    }
    return result;
  }
}
