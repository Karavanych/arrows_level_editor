import 'package:flutter/material.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_painter.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';

class ArrowsViewBoardWidget extends StatelessWidget {
  const ArrowsViewBoardWidget({super.key, required this.model});

  final ArrowsViewRuntimeModel model;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: ArrowsViewBoardPainter(model: model),
        size: Size.infinite,
      ),
    );
  }
}
