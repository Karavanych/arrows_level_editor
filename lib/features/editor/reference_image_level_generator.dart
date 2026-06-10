import 'dart:io';

import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ReferenceImageLevelGenerator {
  const ReferenceImageLevelGenerator();

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
          cells: _sampleImageCells(
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
}
