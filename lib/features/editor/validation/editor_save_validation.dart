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

      if (_lineAnalyzer.componentHasStartMarker(state, component)) {
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
      if (_lineAnalyzer.componentHasStartMarker(state, component)) {
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
      nextCells[candidate] = current.copyWith(hasStartMarker: true);
    }

    return state.copyWith(cells: nextCells, clearSelectedCell: true);
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
