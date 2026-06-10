import 'dart:async';

import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_line_analyzer.dart';

class CheckPreviewSimulationOutcome {
  const CheckPreviewSimulationOutcome({
    required this.passed,
    required this.finalState,
    required this.startPlanState,
    required this.usedOppositeStarts,
    required this.message,
  });

  final bool passed;
  final EditorState finalState;
  final EditorState startPlanState;
  final bool usedOppositeStarts;
  final String message;
}

typedef CheckPreviewStepCallback =
    FutureOr<void> Function(EditorState state, String statusText);
typedef CheckPreviewBlockedCallback = FutureOr<bool> Function();

class EditorCheckPreviewSimulationService {
  EditorCheckPreviewSimulationService({EditorLineAnalyzer? lineAnalyzer})
    : _lineAnalyzer = lineAnalyzer ?? const EditorLineAnalyzer();

  final EditorLineAnalyzer _lineAnalyzer;

  Future<CheckPreviewSimulationOutcome> run({
    required EditorState baseState,
    required CheckPreviewStepCallback onStep,
    required CheckPreviewBlockedCallback onBlocked,
    Duration stepDelay = const Duration(milliseconds: 250),
  }) async {
    final working = _WorkingCopy(baseState);
    var usedOppositeStarts = false;
    await onStep(working.toState(baseState), 'running');

    while (true) {
      final currentState = working.toState(baseState);
      final components = _lineAnalyzer.findColorConnectedComponents(currentState);
      if (components.isEmpty) {
        final finalState = working.toState(baseState);
        await onStep(finalState, 'passed');
        return CheckPreviewSimulationOutcome(
          passed: true,
          finalState: finalState,
          startPlanState: working.toStartPlanState(baseState),
          usedOppositeStarts: usedOppositeStarts,
          message: 'All lines removed.',
        );
      }

      var removedAny = false;
      for (final component in components) {
        final iterationState = working.toState(baseState);
        final startIndex = _findStartIndex(iterationState, component);
        final direction = _deriveForwardDirection(
          state: iterationState,
          component: component,
          startIndex: startIndex,
        );
        if (direction == null) {
          continue;
        }
        final blocked = _hasOccupiedAhead(
          state: iterationState,
          startIndex: startIndex,
          dx: direction.dx,
          dy: direction.dy,
        );
        if (blocked) {
          continue;
        }

        working.removeComponent(component);
        removedAny = true;
        await onStep(working.toState(baseState), 'running');
        if (stepDelay > Duration.zero) {
          await Future<void>.delayed(stepDelay);
        }
      }

      if (removedAny) {
        continue;
      }

      await onStep(working.toState(baseState), 'failed');
      final shouldTryOppositeStarts = await onBlocked();
      if (!shouldTryOppositeStarts) {
        return CheckPreviewSimulationOutcome(
          passed: false,
          finalState: working.toState(baseState),
          startPlanState: working.toStartPlanState(baseState),
          usedOppositeStarts: usedOppositeStarts,
          message: 'Lines block each other.',
        );
      }

      final removedWithOppositeStart = _tryRemoveBlockedComponentWithOppositeStart(
        working: working,
        baseState: baseState,
        components: components,
      );
      if (!removedWithOppositeStart) {
        return CheckPreviewSimulationOutcome(
          passed: false,
          finalState: working.toState(baseState),
          startPlanState: working.toStartPlanState(baseState),
          usedOppositeStarts: usedOppositeStarts,
          message: 'Failed to find opposite endpoints for blocked lines.',
        );
      }
      usedOppositeStarts = true;
      await onStep(working.toState(baseState), 'running');
      if (stepDelay > Duration.zero) {
        await Future<void>.delayed(stepDelay);
      }
    }
  }

  int _findStartIndex(EditorState state, ColorConnectedComponent component) {
    for (final index in component.cellIndices) {
      if (state.cells[index].hasStartMarker) {
        return index;
      }
    }
    return component.cellIndices.first;
  }

  ({int dx, int dy})? _deriveForwardDirection({
    required EditorState state,
    required ColorConnectedComponent component,
    required int startIndex,
  }) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    final startX = startIndex % width;
    final startY = startIndex ~/ width;
    final colorArgb = component.colorArgb;
    final candidates = <({int x, int y})>[
      (x: startX - 1, y: startY),
      (x: startX + 1, y: startY),
      (x: startX, y: startY - 1),
      (x: startX, y: startY + 1),
    ];
    for (final candidate in candidates) {
      if (candidate.x < 0 ||
          candidate.y < 0 ||
          candidate.x >= width ||
          candidate.y >= height) {
        continue;
      }
      final neighborIndex = candidate.y * width + candidate.x;
      final neighborCell = state.cells[neighborIndex];
      final neighborColor = neighborCell.paintColor?.toARGB32();
      if (neighborCell.isInactive || neighborColor != colorArgb) {
        continue;
      }
      return (dx: startX - candidate.x, dy: startY - candidate.y);
    }
    return null;
  }

  bool _hasOccupiedAhead({
    required EditorState state,
    required int startIndex,
    required int dx,
    required int dy,
  }) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    var x = (startIndex % width) + dx;
    var y = (startIndex ~/ width) + dy;
    while (x >= 0 && y >= 0 && x < width && y < height) {
      final cell = state.cells[y * width + x];
      if (!cell.isInactive && cell.paintColor != null) {
        return true;
      }
      x += dx;
      y += dy;
    }
    return false;
  }

  bool _tryRemoveBlockedComponentWithOppositeStart({
    required _WorkingCopy working,
    required EditorState baseState,
    required List<ColorConnectedComponent> components,
  }) {
    for (final component in components) {
      final stateBeforeSwap = working.toState(baseState);
      final startIndex = _findStartIndex(stateBeforeSwap, component);
      final oppositeEndpoint = _findOppositeEndpoint(
        state: stateBeforeSwap,
        component: component,
        startIndex: startIndex,
      );
      if (oppositeEndpoint == null) {
        continue;
      }

      working.replaceComponentStarts(component, oppositeEndpoint);
      final stateAfterSwap = working.toState(baseState);
      final swappedStart = _findStartIndex(stateAfterSwap, component);
      final direction = _deriveForwardDirection(
        state: stateAfterSwap,
        component: component,
        startIndex: swappedStart,
      );
      if (direction == null ||
          _hasOccupiedAhead(
            state: stateAfterSwap,
            startIndex: swappedStart,
            dx: direction.dx,
            dy: direction.dy,
          )) {
        working.replaceComponentStarts(component, startIndex);
        continue;
      }

      working.removeComponent(component);
      return true;
    }

    return false;
  }

  int? _findOppositeEndpoint({
    required EditorState state,
    required ColorConnectedComponent component,
    required int startIndex,
  }) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    final endpoints = <int>[];

    for (final index in component.cellIndices) {
      var sameColorNeighbors = 0;
      final x = index % width;
      final y = index ~/ width;
      final neighbors = <({int x, int y})>[
        (x: x - 1, y: y),
        (x: x + 1, y: y),
        (x: x, y: y - 1),
        (x: x, y: y + 1),
      ];
      for (final neighbor in neighbors) {
        if (neighbor.x < 0 ||
            neighbor.y < 0 ||
            neighbor.x >= width ||
            neighbor.y >= height) {
          continue;
        }
        final neighborCell = state.cells[neighbor.y * width + neighbor.x];
        final neighborColor = neighborCell.paintColor?.toARGB32();
        if (!neighborCell.isInactive && neighborColor == component.colorArgb) {
          sameColorNeighbors += 1;
        }
      }
      if (sameColorNeighbors == 1) {
        endpoints.add(index);
      }
    }

    for (final endpoint in endpoints) {
      if (endpoint != startIndex) {
        return endpoint;
      }
    }
    return null;
  }
}

class _WorkingCopy {
  _WorkingCopy(EditorState baseState)
    : _cells = List<EditorCell>.from(baseState.cells),
      _startPlanCells = List<EditorCell>.from(baseState.cells);

  final List<EditorCell> _cells;
  final List<EditorCell> _startPlanCells;

  void removeComponent(ColorConnectedComponent component) {
    for (final index in component.cellIndices) {
      _cells[index] = const EditorCell();
    }
  }

  void replaceComponentStarts(ColorConnectedComponent component, int startIndex) {
    for (final index in component.cellIndices) {
      final current = _cells[index];
      if (current.hasStartMarker) {
        _cells[index] = current.copyWith(hasStartMarker: false);
      }
      final startPlanCurrent = _startPlanCells[index];
      if (startPlanCurrent.hasStartMarker) {
        _startPlanCells[index] = startPlanCurrent.copyWith(hasStartMarker: false);
      }
    }
    final currentStart = _cells[startIndex];
    _cells[startIndex] = currentStart.copyWith(hasStartMarker: true);
    final startPlanStart = _startPlanCells[startIndex];
    _startPlanCells[startIndex] = startPlanStart.copyWith(hasStartMarker: true);
  }

  EditorState toState(EditorState baseState) {
    return baseState.copyWith(
      cells: List<EditorCell>.from(_cells),
      clearSelectedCell: true,
    );
  }

  EditorState toStartPlanState(EditorState baseState) {
    return baseState.copyWith(
      cells: List<EditorCell>.from(_startPlanCells),
      clearSelectedCell: true,
    );
  }
}
