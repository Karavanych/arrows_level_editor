import 'dart:collection';

import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_line_analyzer.dart';

enum SaveValidationProblemCode {
  emptyCells,
  singleCellColorIsland,
  missingLineStart,
  linePathReconstructionFailed,
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
          message: 'Уровень содержит пустые клетки.',
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
            message: 'Одноклеточный цветовой остров недопустим.',
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
          message: 'У цветовой связной линии нет стартовой точки.',
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

  List<SaveValidationProblem> validatePathReconstruction(EditorState state) {
    final components = _lineAnalyzer.findColorConnectedComponents(state);
    final problems = <SaveValidationProblem>[];
    for (final component in components) {
      final failure = _validateComponentPathReconstruction(
        state: state,
        component: component,
      );
      if (failure == null) {
        continue;
      }
      problems.add(
        SaveValidationProblem(
          code: SaveValidationProblemCode.linePathReconstructionFailed,
          message: failure.message,
          isBlocking: true,
          cellIndices: failure.cellIndices,
          componentId: component.id,
        ),
      );
    }
    return problems;
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

  _PathReconstructionFailure? _validateComponentPathReconstruction({
    required EditorState state,
    required ColorConnectedComponent component,
  }) {
    final componentIndices = List<int>.from(component.cellIndices)..sort();
    if (componentIndices.length < 2) {
      return _PathReconstructionFailure(
        message: 'не удалось восстановить путь линии',
        cellIndices: componentIndices,
      );
    }

    final startCandidates = componentIndices.where((index) {
      final cell = state.cells[index];
      return cell.hasStartMarker && cell.startDirection != null;
    }).toList()
      ..sort();
    if (startCandidates.isEmpty) {
      return _PathReconstructionFailure(
        message: 'не удалось восстановить путь линии',
        cellIndices: componentIndices,
      );
    }
    if (startCandidates.length > 1) {
      return _PathReconstructionFailure(
        message: 'не удалось восстановить путь линии',
        cellIndices: componentIndices,
      );
    }

    final startIndex = startCandidates.first;
    if (!componentIndices.contains(startIndex)) {
      return _PathReconstructionFailure(
        message: 'не удалось восстановить путь линии',
        cellIndices: componentIndices,
      );
    }
    final startCell = state.cells[startIndex];
    final startDirection = startCell.startDirection;
    if (startDirection == null) {
      return _PathReconstructionFailure(
        message: 'не удалось восстановить путь линии',
        cellIndices: componentIndices,
      );
    }

    final inComponent = List<bool>.filled(state.cells.length, false);
    for (final index in componentIndices) {
      inComponent[index] = true;
    }

    final expectedNeighbor = _expectedNeighborIndex(
      state: state,
      startIndex: startIndex,
      direction: startDirection,
    );
    if (expectedNeighbor == null || !inComponent[expectedNeighbor]) {
      return _PathReconstructionFailure(
        message: 'направление старта несовместимо с геометрией компонента',
        cellIndices: componentIndices,
      );
    }

    final reconstructed = _searchPathDeterministic(
      state: state,
      component: componentIndices,
      inComponent: inComponent,
      startIndex: startIndex,
      startNeighbor: expectedNeighbor,
    );
    if (reconstructed == null) {
      return _PathReconstructionFailure(
        message: 'для компонента не найден корректный путь реконструкции',
        cellIndices: componentIndices,
      );
    }

    return null;
  }

  List<int>? _searchPathDeterministic({
    required EditorState state,
    required List<int> component,
    required List<bool> inComponent,
    required int startIndex,
    required int startNeighbor,
  }) {
    final nonStartCount = component.length - 1;
    if (nonStartCount <= 0) {
      return null;
    }

    final walk = List<int>.filled(nonStartCount, -1);
    final visited = List<bool>.filled(inComponent.length, false);
    visited[startIndex] = true;
    visited[startNeighbor] = true;
    walk[0] = startNeighbor;

    final found = _searchPathDfs(
      state: state,
      inComponent: inComponent,
      visited: visited,
      startIndex: startIndex,
      current: startNeighbor,
      walk: walk,
      depth: 1,
      nonStartCount: nonStartCount,
    );
    if (!found) {
      return null;
    }

    final path = <int>[];
    for (var i = nonStartCount - 1; i >= 0; i -= 1) {
      path.add(walk[i]);
    }
    path.add(startIndex);
    return path;
  }

  bool _searchPathDfs({
    required EditorState state,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int current,
    required List<int> walk,
    required int depth,
    required int nonStartCount,
  }) {
    if (depth == nonStartCount) {
      return true;
    }
    if (!_isResidualConnected(
      state: state,
      inComponent: inComponent,
      visited: visited,
      startIndex: startIndex,
      current: current,
    )) {
      return false;
    }

    final candidates = _collectOrderedCandidates(
      state: state,
      inComponent: inComponent,
      visited: visited,
      startIndex: startIndex,
      current: current,
    );
    if (candidates.isEmpty) {
      return false;
    }

    for (final next in candidates) {
      visited[next] = true;
      walk[depth] = next;
      if (_searchPathDfs(
        state: state,
        inComponent: inComponent,
        visited: visited,
        startIndex: startIndex,
        current: next,
        walk: walk,
        depth: depth + 1,
        nonStartCount: nonStartCount,
      )) {
        return true;
      }
      visited[next] = false;
    }
    return false;
  }

  List<int> _collectOrderedCandidates({
    required EditorState state,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int current,
  }) {
    final candidates = <int>[];
    for (final neighbor in _neighbors4(state: state, index: current)) {
      if (!inComponent[neighbor] || visited[neighbor] || neighbor == startIndex) {
        continue;
      }
      candidates.add(neighbor);
    }
    candidates.sort((a, b) {
      final degreeA = _countResidualDegree(
        state: state,
        inComponent: inComponent,
        visited: visited,
        startIndex: startIndex,
        node: a,
      );
      final degreeB = _countResidualDegree(
        state: state,
        inComponent: inComponent,
        visited: visited,
        startIndex: startIndex,
        node: b,
      );
      if (degreeA != degreeB) {
        return degreeA.compareTo(degreeB);
      }
      return a.compareTo(b);
    });
    return candidates;
  }

  bool _isResidualConnected({
    required EditorState state,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int current,
  }) {
    final seen = List<bool>.filled(inComponent.length, false);
    final queue = Queue<int>()..add(current);
    seen[current] = true;
    var reachable = 0;

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      reachable += 1;
      for (final neighbor in _neighbors4(state: state, index: node)) {
        if (!inComponent[neighbor] ||
            neighbor == startIndex ||
            seen[neighbor]) {
          continue;
        }
        if (visited[neighbor] && neighbor != current) {
          continue;
        }
        seen[neighbor] = true;
        queue.add(neighbor);
      }
    }

    var residual = 0;
    for (var i = 0; i < inComponent.length; i += 1) {
      if (!inComponent[i] || i == startIndex) {
        continue;
      }
      if (!visited[i] || i == current) {
        residual += 1;
      }
    }
    return reachable == residual;
  }

  int _countResidualDegree({
    required EditorState state,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int node,
  }) {
    var degree = 0;
    for (final neighbor in _neighbors4(state: state, index: node)) {
      if (!inComponent[neighbor] || neighbor == startIndex) {
        continue;
      }
      if (!visited[neighbor]) {
        degree += 1;
      }
    }
    return degree;
  }

  int? _expectedNeighborIndex({
    required EditorState state,
    required int startIndex,
    required StartDirection direction,
  }) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    final x = startIndex % width;
    final y = startIndex ~/ width;
    final (dx, dy) = switch (direction) {
      StartDirection.left => (1, 0),
      StartDirection.right => (-1, 0),
      StartDirection.up => (0, 1),
      StartDirection.down => (0, -1),
    };
    final nx = x + dx;
    final ny = y + dy;
    if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
      return null;
    }
    return ny * width + nx;
  }

  Iterable<int> _neighbors4({
    required EditorState state,
    required int index,
  }) sync* {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
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
}

class _PathReconstructionFailure {
  const _PathReconstructionFailure({
    required this.message,
    required this.cellIndices,
  });

  final String message;
  final List<int> cellIndices;
}
