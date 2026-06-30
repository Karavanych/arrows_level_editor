import 'dart:collection';
import 'dart:ui';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_level_snapshot.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';

class ArrowsViewPathReconstructor {
  static const List<Offset> _neighborSteps = <Offset>[
    Offset(1, 0),
    Offset(-1, 0),
    Offset(0, 1),
    Offset(0, -1),
  ];

  ArrowsViewRuntimeModel build(ArrowsViewLevelSnapshot snapshot) {
    final width = snapshot.gridWidth;
    final height = snapshot.gridHeight;
    final expectedCellCount = width * height;
    if (width <= 0 ||
        height <= 0 ||
        snapshot.cells.length != expectedCellCount) {
      throw const ArrowsViewRuntimeBuildException(
        'Invalid snapshot grid dimensions.',
      );
    }

    final activeMask = List<bool>.filled(expectedCellCount, false);
    final colorByCell = List<int?>.filled(expectedCellCount, null);
    for (final cell in snapshot.cells) {
      if (!_isInside(width, height, cell.x, cell.y)) {
        throw const ArrowsViewRuntimeBuildException(
          'Snapshot contains a cell outside board bounds.',
        );
      }
      if (cell.index < 0 || cell.index >= expectedCellCount) {
        throw const ArrowsViewRuntimeBuildException(
          'Snapshot contains an invalid cell index.',
        );
      }
      if (_indexOf(width, cell.x, cell.y) != cell.index) {
        throw const ArrowsViewRuntimeBuildException(
          'Snapshot cell coordinates do not match cell index.',
        );
      }
      final isActive = !cell.isInactive && cell.paintColorValue != null;
      activeMask[cell.index] = isActive;
      colorByCell[cell.index] = isActive ? cell.paintColorValue : null;
    }

    final visited = List<bool>.filled(expectedCellCount, false);
    final paths = <ArrowsViewRenderPath>[];

    for (final start in snapshot.startPoints) {
      _validateStartInsideBoard(width, height, start);
      final startIndex = _indexOf(width, start.x, start.y);
      if (!activeMask[startIndex]) {
        throw ArrowsViewRuntimeBuildException(
          'Start point is on an inactive cell at (${start.x}, ${start.y}).',
        );
      }
      if (visited[startIndex]) {
        throw const ArrowsViewRuntimeBuildException(
          'Multiple start points resolve to the same color region.',
        );
      }
      final color = colorByCell[startIndex];
      if (color == null) {
        throw const ArrowsViewRuntimeBuildException(
          'Start point has no playable color.',
        );
      }

      final cellPath = _reconstructPathFromStart(
        width: width,
        height: height,
        colorByCell: colorByCell,
        visited: visited,
        start: start,
        color: color,
      );
      if (cellPath.length < 2) {
        throw const ArrowsViewRuntimeBuildException(
          'Line path must contain at least two cells.',
        );
      }

      final points = cellPath
          .map((index) {
            return Offset(
              (index % width).toDouble(),
              (index ~/ width).toDouble(),
            );
          })
          .toList(growable: false);
      final head = points.last;
      final previous = points[points.length - 2];
      final direction = _normalize(head - previous);
      paths.add(
        ArrowsViewRenderPath(
          colorValue: color,
          cellIndices: cellPath,
          points: points,
          headPose: ArrowsViewHeadPose(position: head, direction: direction),
        ),
      );
    }

    for (var index = 0; index < colorByCell.length; index += 1) {
      if (colorByCell[index] != null && !visited[index]) {
        final y = index ~/ width;
        final x = index % width;
        throw ArrowsViewRuntimeBuildException(
          'Found colored playable cell without matching start point at ($x, $y).',
        );
      }
    }

    return ArrowsViewRuntimeModel(
      levelId: snapshot.levelId,
      width: width,
      height: height,
      activeMask: activeMask,
      colorByCell: colorByCell,
      paths: paths,
    );
  }

  List<int> _reconstructPathFromStart({
    required int width,
    required int height,
    required List<int?> colorByCell,
    required List<bool> visited,
    required ArrowsViewStartPointSnapshot start,
    required int color,
  }) {
    final component = _collectComponent(
      width: width,
      height: height,
      colorByCell: colorByCell,
      startX: start.x,
      startY: start.y,
      color: color,
    )..sort();

    final inComponent = List<bool>.filled(colorByCell.length, false);
    for (final index in component) {
      inComponent[index] = true;
    }

    final startIndex = _indexOf(width, start.x, start.y);
    if (!inComponent[startIndex]) {
      throw const ArrowsViewRuntimeBuildException(
        'Start point does not belong to its color component.',
      );
    }
    if (component.length < 2) {
      throw const ArrowsViewRuntimeBuildException(
        'Line path must contain at least two cells.',
      );
    }

    final startNeighbor = _expectedNeighborIndex(
      width: width,
      height: height,
      start: start,
      inComponent: inComponent,
    );
    final path = _searchPathDeterministic(
      width: width,
      component: component,
      inComponent: inComponent,
      startIndex: startIndex,
      startNeighbor: startNeighbor,
    );
    if (path == null) {
      throw const ArrowsViewRuntimeBuildException(
        'No valid path reconstruction exists for this color region and start direction.',
      );
    }
    for (final index in path) {
      visited[index] = true;
    }
    return path;
  }

  List<int>? _searchPathDeterministic({
    required int width,
    required List<int> component,
    required List<bool> inComponent,
    required int startIndex,
    required int startNeighbor,
  }) {
    final nonStartCount = component.length - 1;
    final walk = List<int>.filled(nonStartCount, -1);
    final visited = List<bool>.filled(inComponent.length, false);
    visited[startIndex] = true;
    visited[startNeighbor] = true;
    walk[0] = startNeighbor;

    final found = _searchPathDfs(
      width: width,
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
    required int width,
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
      width: width,
      inComponent: inComponent,
      visited: visited,
      startIndex: startIndex,
      current: current,
    )) {
      return false;
    }

    final candidates = _collectOrderedCandidates(
      width: width,
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
      final found = _searchPathDfs(
        width: width,
        inComponent: inComponent,
        visited: visited,
        startIndex: startIndex,
        current: next,
        walk: walk,
        depth: depth + 1,
        nonStartCount: nonStartCount,
      );
      if (found) {
        return true;
      }
      visited[next] = false;
    }
    return false;
  }

  List<int> _collectOrderedCandidates({
    required int width,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int current,
  }) {
    final height = inComponent.length ~/ width;
    final x = current % width;
    final y = current ~/ width;
    final candidates = <int>[];
    for (final step in _neighborSteps) {
      final nx = x + step.dx.toInt();
      final ny = y + step.dy.toInt();
      if (!_isInside(width, height, nx, ny)) {
        continue;
      }
      final nIndex = _indexOf(width, nx, ny);
      if (!inComponent[nIndex] || visited[nIndex] || nIndex == startIndex) {
        continue;
      }
      candidates.add(nIndex);
    }

    candidates.sort((a, b) {
      final degreeA = _countResidualDegree(
        width: width,
        inComponent: inComponent,
        visited: visited,
        startIndex: startIndex,
        node: a,
      );
      final degreeB = _countResidualDegree(
        width: width,
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
    required int width,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int current,
  }) {
    final height = inComponent.length ~/ width;
    final seen = List<bool>.filled(inComponent.length, false);
    final queue = Queue<int>()..add(current);
    seen[current] = true;
    var reachable = 0;

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      reachable += 1;
      final x = node % width;
      final y = node ~/ width;
      for (final step in _neighborSteps) {
        final nx = x + step.dx.toInt();
        final ny = y + step.dy.toInt();
        if (!_isInside(width, height, nx, ny)) {
          continue;
        }
        final nIndex = _indexOf(width, nx, ny);
        if (seen[nIndex]) {
          continue;
        }
        if (!inComponent[nIndex] || nIndex == startIndex) {
          continue;
        }
        if (visited[nIndex] && nIndex != current) {
          continue;
        }
        seen[nIndex] = true;
        queue.addLast(nIndex);
      }
    }

    var residual = 0;
    for (var index = 0; index < inComponent.length; index += 1) {
      if (!inComponent[index] || index == startIndex) {
        continue;
      }
      if (!visited[index] || index == current) {
        residual += 1;
      }
    }
    return reachable == residual;
  }

  int _countResidualDegree({
    required int width,
    required List<bool> inComponent,
    required List<bool> visited,
    required int startIndex,
    required int node,
  }) {
    final height = inComponent.length ~/ width;
    final x = node % width;
    final y = node ~/ width;
    var degree = 0;
    for (final step in _neighborSteps) {
      final nx = x + step.dx.toInt();
      final ny = y + step.dy.toInt();
      if (!_isInside(width, height, nx, ny)) {
        continue;
      }
      final nIndex = _indexOf(width, nx, ny);
      if (!inComponent[nIndex] || nIndex == startIndex) {
        continue;
      }
      if (!visited[nIndex]) {
        degree += 1;
      }
    }
    return degree;
  }

  int _expectedNeighborIndex({
    required int width,
    required int height,
    required ArrowsViewStartPointSnapshot start,
    required List<bool> inComponent,
  }) {
    var nx = start.x;
    var ny = start.y;
    switch (start.direction) {
      case 'left':
        nx = start.x + 1;
      case 'right':
        nx = start.x - 1;
      case 'up':
        ny = start.y + 1;
      case 'down':
        ny = start.y - 1;
      default:
        throw ArrowsViewRuntimeBuildException(
          'Unsupported start direction at (${start.x}, ${start.y}).',
        );
    }

    if (!_isInside(width, height, nx, ny)) {
      throw ArrowsViewRuntimeBuildException(
        'Start direction points outside board at (${start.x}, ${start.y}).',
      );
    }
    final neighbor = _indexOf(width, nx, ny);
    if (!inComponent[neighbor]) {
      throw ArrowsViewRuntimeBuildException(
        'Start direction is inconsistent with same-color geometry at (${start.x}, ${start.y}).',
      );
    }
    return neighbor;
  }

  List<int> _collectComponent({
    required int width,
    required int height,
    required List<int?> colorByCell,
    required int startX,
    required int startY,
    required int color,
  }) {
    final startIndex = _indexOf(width, startX, startY);
    final seen = List<bool>.filled(colorByCell.length, false);
    final component = <int>[];
    final queue = Queue<int>()..add(startIndex);
    seen[startIndex] = true;

    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      component.add(index);
      final x = index % width;
      final y = index ~/ width;
      for (final step in _neighborSteps) {
        final nx = x + step.dx.toInt();
        final ny = y + step.dy.toInt();
        if (!_isInside(width, height, nx, ny)) {
          continue;
        }
        final nIndex = _indexOf(width, nx, ny);
        if (seen[nIndex] || colorByCell[nIndex] != color) {
          continue;
        }
        seen[nIndex] = true;
        queue.addLast(nIndex);
      }
    }

    return component;
  }

  void _validateStartInsideBoard(
    int width,
    int height,
    ArrowsViewStartPointSnapshot start,
  ) {
    if (!_isInside(width, height, start.x, start.y)) {
      throw ArrowsViewRuntimeBuildException(
        'Start point is outside board: (${start.x}, ${start.y}).',
      );
    }
  }

  bool _isInside(int width, int height, int x, int y) {
    return x >= 0 && x < width && y >= 0 && y < height;
  }

  int _indexOf(int width, int x, int y) => y * width + x;

  Offset _normalize(Offset vector) {
    final length = vector.distance;
    if (length <= 0.0001) {
      return const Offset(1, 0);
    }
    return Offset(vector.dx / length, vector.dy / length);
  }
}
