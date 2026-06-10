import 'dart:io';
import 'dart:math' as math;

import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ReferenceImageLevelGenerator {
  const ReferenceImageLevelGenerator({
    this.config = const ReferenceImageGenerationConfig(),
  });

  final ReferenceImageGenerationConfig config;

  Future<List<EditorState>> generateLevelsFromReferenceImages({
    required List<String> imagePaths,
    required int gridWidth,
    required int gridHeight,
    required List<Color> paletteColors,
    required Color selectedColor,
    required EditorTool selectedTool,
  }) async {
    if (imagePaths.isEmpty) {
      return const [];
    }

    final levels = <EditorState>[];
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        continue;
      }

      levels.add(
        EditorState(
          gridSize: EditorGridSize(width: gridWidth, height: gridHeight),
          cells: _generateRibbonCells(
            image: image,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
          ),
          selectedColor: selectedColor,
          selectedTool: selectedTool,
          paletteColors: List<Color>.from(paletteColors),
        ),
      );
    }
    return levels;
  }

  List<EditorCell> _generateRibbonCells({
    required img.Image image,
    required int gridWidth,
    required int gridHeight,
  }) {
    final sampledCells = _sampleImageCells(
      image: image,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
    final regions = _buildColorRegions(
      cells: sampledCells,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
    final outputCells = List<EditorCell>.filled(
      gridWidth * gridHeight,
      const EditorCell(isInactive: true),
    );

    for (final region in regions) {
      _fillRegionWithRibbons(
        region: region,
        outputCells: outputCells,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
      );
    }

    for (final region in regions) {
      _fillRemainingActiveRegionCells(region: region, outputCells: outputCells);
    }

    return outputCells;
  }

  List<EditorCell> _sampleImageCells({
    required img.Image image,
    required int gridWidth,
    required int gridHeight,
  }) {
    final cells = <EditorCell>[];
    for (var y = 0; y < gridHeight; y += 1) {
      final sampleY = (((y + 0.5) * image.height) / gridHeight)
          .floor()
          .clamp(0, image.height - 1);
      for (var x = 0; x < gridWidth; x += 1) {
        final sampleX = (((x + 0.5) * image.width) / gridWidth)
            .floor()
            .clamp(0, image.width - 1);
        final pixel = image.getPixel(sampleX, sampleY);
        final alpha = pixel.a.toInt();
        if (alpha == 0) {
          cells.add(const EditorCell(isInactive: true));
          continue;
        }
        cells.add(
          EditorCell(
            paintColor: Color.fromARGB(
              alpha,
              pixel.r.toInt(),
              pixel.g.toInt(),
              pixel.b.toInt(),
            ),
          ),
        );
      }
    }
    return cells;
  }

  List<_ColorRegion> _buildColorRegions({
    required List<EditorCell> cells,
    required int gridWidth,
    required int gridHeight,
  }) {
    final visited = List<bool>.filled(cells.length, false);
    final regions = <_ColorRegion>[];

    for (var index = 0; index < cells.length; index += 1) {
      if (visited[index] || _isInactive(cells[index])) {
        continue;
      }

      final queue = <int>[index];
      final indices = <int>[];
      visited[index] = true;
      var cursor = 0;

      while (cursor < queue.length) {
        final current = queue[cursor];
        cursor += 1;
        indices.add(current);

        for (final neighbor in _neighbors4(
          current,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
        )) {
          if (visited[neighbor] || _isInactive(cells[neighbor])) {
            continue;
          }
          final currentColor = cells[current].paintColor!;
          final neighborColor = cells[neighbor].paintColor!;
          if (_colorDistance(currentColor, neighborColor) >
              config.regionColorTolerance) {
            continue;
          }
          visited[neighbor] = true;
          queue.add(neighbor);
        }
      }

      regions.add(
        _ColorRegion(
          indices: indices,
          baseColor: _averageColor(indices.map((it) => cells[it].paintColor!)),
        ),
      );
    }

    return regions;
  }

  void _fillRegionWithRibbons({
    required _ColorRegion region,
    required List<EditorCell> outputCells,
    required int gridWidth,
    required int gridHeight,
  }) {
    if (region.indices.isEmpty) {
      return;
    }

    final regionSet = region.indices.toSet();
    final used = <int>{};
    final lineCount = (region.indices.length / config.targetCellsPerLine)
        .round()
        .clamp(1, config.maxLinesPerRegion);
    final seeds = _chooseSeeds(
      region: region,
      lineCount: lineCount,
      gridWidth: gridWidth,
    );
    final lines = <_RibbonLine>[];

    for (var i = 0; i < seeds.length; i += 1) {
      final seed = seeds[i];
      if (used.contains(seed)) {
        continue;
      }
      final color = _variantColor(
        baseColor: region.baseColor,
        variantIndex: i,
        variantCount: seeds.length,
      );
      final line = _RibbonLine(color: color)..indices.add(seed);
      lines.add(line);
      used.add(seed);
      outputCells[seed] = EditorCell(paintColor: color);
    }

    var progress = true;
    while (progress) {
      progress = false;
      for (final line in lines) {
        if (line.isStopped || line.indices.length >= config.maxLineLength) {
          line.isStopped = true;
          continue;
        }

        final next = _bestGrowthCandidate(
          line: line,
          regionSet: regionSet,
          used: used,
          outputCells: outputCells,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
        );
        if (next == null) {
          line.isStopped = true;
          continue;
        }

        if (line.indices.length >= config.minLineLength &&
            line.indices.length >= config.targetLineLength &&
            next.score < 0) {
          line.isStopped = true;
          continue;
        }

        if (next.growAtHead) {
          line.indices.add(next.index);
        } else {
          line.indices.insert(0, next.index);
        }
        used.add(next.index);
        outputCells[next.index] = EditorCell(paintColor: line.color);
        progress = true;
      }
    }

    _attachLeftoversToRibbonEndpoints(
      lines: lines,
      regionSet: regionSet,
      used: used,
      outputCells: outputCells,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );

    for (var pass = 0; pass < config.cleanupPasses; pass += 1) {
      _cleanupObviousBlocks(
        lines: lines,
        outputCells: outputCells,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
      );
    }

    _fillRemainingActiveRegionCells(region: region, outputCells: outputCells);
  }

  List<int> _chooseSeeds({
    required _ColorRegion region,
    required int lineCount,
    required int gridWidth,
  }) {
    final seeds = <int>[];
    final cells = List<int>.from(region.indices);
    if (cells.isEmpty) {
      return seeds;
    }

    final centroidX =
        cells.map((it) => it % gridWidth).reduce((a, b) => a + b) /
        cells.length;
    final centroidY =
        cells.map((it) => it ~/ gridWidth).reduce((a, b) => a + b) /
        cells.length;
    cells.sort((a, b) {
      final ad = _distanceSquared(a, centroidX, centroidY, gridWidth);
      final bd = _distanceSquared(b, centroidX, centroidY, gridWidth);
      return ad.compareTo(bd);
    });
    seeds.add(cells.first);

    while (seeds.length < lineCount && seeds.length < cells.length) {
      int? best;
      var bestDistance = -1;
      for (final candidate in cells) {
        if (seeds.contains(candidate)) {
          continue;
        }
        final minDistance = seeds
            .map((seed) => _manhattan(seed, candidate, gridWidth))
            .reduce(math.min);
        if (minDistance < config.seedSpacing && cells.length > lineCount) {
          continue;
        }
        if (minDistance > bestDistance) {
          bestDistance = minDistance;
          best = candidate;
        }
      }
      best ??= cells.firstWhere((cell) => !seeds.contains(cell));
      seeds.add(best);
    }

    return seeds;
  }

  _GrowthCandidate? _bestGrowthCandidate({
    required _RibbonLine line,
    required Set<int> regionSet,
    required Set<int> used,
    required List<EditorCell> outputCells,
    required int gridWidth,
    required int gridHeight,
  }) {
    final candidates = <_GrowthCandidate>[];
    for (final growAtHead in [true, false]) {
      final endpoint = growAtHead ? line.indices.last : line.indices.first;
      for (final neighbor in _neighbors4(
        endpoint,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
      )) {
        if (!regionSet.contains(neighbor) || used.contains(neighbor)) {
          continue;
        }
        if (_sameLineNeighborCount(
              neighbor,
              line,
              gridWidth: gridWidth,
              gridHeight: gridHeight,
            ) >
            1) {
          continue;
        }
        candidates.add(
          _GrowthCandidate(
            index: neighbor,
            growAtHead: growAtHead,
            score: _scoreCandidate(
              candidate: neighbor,
              line: line,
              growAtHead: growAtHead,
              outputCells: outputCells,
              gridWidth: gridWidth,
              gridHeight: gridHeight,
            ),
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first;
  }

  double _scoreCandidate({
    required int candidate,
    required _RibbonLine line,
    required bool growAtHead,
    required List<EditorCell> outputCells,
    required int gridWidth,
    required int gridHeight,
  }) {
    var score = 0.0;
    if (line.indices.length >= 2) {
      final endpoint = growAtHead ? line.indices.last : line.indices.first;
      final previous = growAtHead
          ? line.indices[line.indices.length - 2]
          : line.indices[1];
      final previousDx = (endpoint % gridWidth) - (previous % gridWidth);
      final previousDy = (endpoint ~/ gridWidth) - (previous ~/ gridWidth);
      final nextDx = (candidate % gridWidth) - (endpoint % gridWidth);
      final nextDy = (candidate ~/ gridWidth) - (endpoint ~/ gridWidth);
      if (previousDx == nextDx && previousDy == nextDy) {
        score += config.straightPreference;
      } else {
        score += config.turnPreference;
      }
    }

    final activeNeighbors = _activeNeighborCount(
      candidate,
      outputCells,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
    score -= activeNeighbors * config.sameFamilyCrowdingPenalty;
    score -=
        _twoByTwoActiveBlockCount(
          candidate,
          outputCells,
          gridWidth,
          gridHeight,
          assumeActiveIndex: candidate,
        ) *
        config.blobPenalty;

    if (line.indices.length < config.minLineLength) {
      final futureOptions = _neighbors4(
        candidate,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
      ).where((it) => _isInactive(outputCells[it])).length;
      score += futureOptions * 0.15;
    }

    return score;
  }

  void _attachLeftoversToRibbonEndpoints({
    required List<_RibbonLine> lines,
    required Set<int> regionSet,
    required Set<int> used,
    required List<EditorCell> outputCells,
    required int gridWidth,
    required int gridHeight,
  }) {
    var progress = true;
    while (progress) {
      progress = false;
      for (final line in lines) {
        if (line.indices.length >= config.maxLineLength) {
          continue;
        }
        final next = _bestGrowthCandidate(
          line: line,
          regionSet: regionSet,
          used: used,
          outputCells: outputCells,
          gridWidth: gridWidth,
          gridHeight: gridHeight,
        );
        if (next == null || next.score < -config.blobPenalty) {
          continue;
        }
        if (next.growAtHead) {
          line.indices.add(next.index);
        } else {
          line.indices.insert(0, next.index);
        }
        used.add(next.index);
        outputCells[next.index] = EditorCell(paintColor: line.color);
        progress = true;
      }
    }
  }

  void _cleanupObviousBlocks({
    required List<_RibbonLine> lines,
    required List<EditorCell> outputCells,
    required int gridWidth,
    required int gridHeight,
  }) {
    for (final line in lines) {
      while (line.indices.length > config.minLineLength) {
        final head = line.indices.last;
        final tail = line.indices.first;
        final headBlocks = _twoByTwoActiveBlockCount(
          head,
          outputCells,
          gridWidth,
          gridHeight,
        );
        final tailBlocks = _twoByTwoActiveBlockCount(
          tail,
          outputCells,
          gridWidth,
          gridHeight,
        );
        if (headBlocks == 0 && tailBlocks == 0) {
          break;
        }
        final removeHead = headBlocks >= tailBlocks;
        final removed = removeHead ? line.indices.removeLast() : line.indices.removeAt(0);
        outputCells[removed] = EditorCell(paintColor: line.color);
      }
    }
  }

  void _fillRemainingActiveRegionCells({
    required _ColorRegion region,
    required List<EditorCell> outputCells,
  }) {
    for (final index in region.indices) {
      if (!_isInactive(outputCells[index])) {
        continue;
      }
      outputCells[index] = EditorCell(paintColor: region.baseColor);
    }
  }

  Iterable<int> _neighbors4(
    int index, {
    required int gridWidth,
    required int gridHeight,
  }) sync* {
    final x = index % gridWidth;
    final y = index ~/ gridWidth;
    if (x > 0) {
      yield index - 1;
    }
    if (x < gridWidth - 1) {
      yield index + 1;
    }
    if (y > 0) {
      yield index - gridWidth;
    }
    if (y < gridHeight - 1) {
      yield index + gridWidth;
    }
  }

  bool _isInactive(EditorCell cell) {
    return cell.isInactive || cell.paintColor == null;
  }

  double _colorDistance(Color a, Color b) {
    final dr = ((a.toARGB32() >> 16) & 0xFF) - ((b.toARGB32() >> 16) & 0xFF);
    final dg = ((a.toARGB32() >> 8) & 0xFF) - ((b.toARGB32() >> 8) & 0xFF);
    final db = (a.toARGB32() & 0xFF) - (b.toARGB32() & 0xFF);
    return math.sqrt((dr * dr) + (dg * dg) + (db * db));
  }

  Color _averageColor(Iterable<Color> colors) {
    var count = 0;
    var r = 0;
    var g = 0;
    var b = 0;
    for (final color in colors) {
      final argb = color.toARGB32();
      r += (argb >> 16) & 0xFF;
      g += (argb >> 8) & 0xFF;
      b += argb & 0xFF;
      count += 1;
    }
    if (count == 0) {
      return Colors.black;
    }
    return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
  }

  Color _variantColor({
    required Color baseColor,
    required int variantIndex,
    required int variantCount,
  }) {
    final hsv = HSVColor.fromColor(baseColor);
    final center = (variantCount - 1) / 2;
    final valueShift = (variantIndex - center) * config.variantLightnessStep;
    final nextValue = (hsv.value + valueShift).clamp(0.12, 1.0);
    return hsv.withValue(nextValue).toColor();
  }

  int _sameLineNeighborCount(
    int index,
    _RibbonLine line, {
    required int gridWidth,
    required int gridHeight,
  }) {
    final lineSet = line.indices.toSet();
    return _neighbors4(index, gridWidth: gridWidth, gridHeight: gridHeight)
        .where(lineSet.contains)
        .length;
  }

  int _activeNeighborCount(
    int index,
    List<EditorCell> cells, {
    required int gridWidth,
    required int gridHeight,
  }) {
    return _neighbors4(index, gridWidth: gridWidth, gridHeight: gridHeight)
        .where((neighbor) => !_isInactive(cells[neighbor]))
        .length;
  }

  int _twoByTwoActiveBlockCount(
    int index,
    List<EditorCell> cells,
    int gridWidth,
    int gridHeight, {
    int? assumeActiveIndex,
  }) {
    final x = index % gridWidth;
    final y = index ~/ gridWidth;
    var count = 0;
    for (final topLeftX in [x - 1, x]) {
      for (final topLeftY in [y - 1, y]) {
        if (topLeftX < 0 ||
            topLeftY < 0 ||
            topLeftX >= gridWidth - 1 ||
            topLeftY >= gridHeight - 1) {
          continue;
        }
        final indices = [
          topLeftY * gridWidth + topLeftX,
          topLeftY * gridWidth + topLeftX + 1,
          (topLeftY + 1) * gridWidth + topLeftX,
          (topLeftY + 1) * gridWidth + topLeftX + 1,
        ];
        if (indices.every(
          (it) => it == assumeActiveIndex || !_isInactive(cells[it]),
        )) {
          count += 1;
        }
      }
    }
    return count;
  }

  int _manhattan(int a, int b, int gridWidth) {
    return ((a % gridWidth) - (b % gridWidth)).abs() +
        ((a ~/ gridWidth) - (b ~/ gridWidth)).abs();
  }

  double _distanceSquared(
    int index,
    double x,
    double y,
    int gridWidth,
  ) {
    final dx = (index % gridWidth) - x;
    final dy = (index ~/ gridWidth) - y;
    return (dx * dx) + (dy * dy);
  }
}

class ReferenceImageGenerationConfig {
  const ReferenceImageGenerationConfig({
    this.targetCellsPerLine = 10,
    this.minLineLength = 4,
    this.targetLineLength = 8,
    this.maxLineLength = 16,
    this.maxLinesPerRegion = 8,
    this.seedSpacing = 3,
    this.turnPreference = 0.35,
    this.straightPreference = 0.55,
    this.blobPenalty = 1.0,
    this.sameFamilyCrowdingPenalty = 0.7,
    this.variantLightnessStep = 0.08,
    this.regionColorTolerance = 24,
    this.cleanupPasses = 2,
  });

  final int targetCellsPerLine;
  final int minLineLength;
  final int targetLineLength;
  final int maxLineLength;
  final int maxLinesPerRegion;
  final int seedSpacing;
  final double turnPreference;
  final double straightPreference;
  final double blobPenalty;
  final double sameFamilyCrowdingPenalty;
  final double variantLightnessStep;
  final double regionColorTolerance;
  final int cleanupPasses;
}

class _ColorRegion {
  const _ColorRegion({required this.indices, required this.baseColor});

  final List<int> indices;
  final Color baseColor;
}

class _RibbonLine {
  _RibbonLine({required this.color});

  final Color color;
  final List<int> indices = [];
  bool isStopped = false;
}

class _GrowthCandidate {
  const _GrowthCandidate({
    required this.index,
    required this.growAtHead,
    required this.score,
  });

  final int index;
  final bool growAtHead;
  final double score;
}
