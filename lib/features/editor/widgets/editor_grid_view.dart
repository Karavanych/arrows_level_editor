import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:flutter/material.dart';

class EditorGridView extends StatelessWidget {
  const EditorGridView({
    super.key,
    required this.state,
    required this.onStrokeStart,
    required this.onCellDrag,
    required this.onStrokeEnd,
  });

  final EditorState state;
  final ValueChanged<int> onStrokeStart;
  final ValueChanged<int> onCellDrag;
  final VoidCallback onStrokeEnd;

  static const double _cellSize = 48;

  @override
  Widget build(BuildContext context) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final index = _indexFromLocalPosition(details.localPosition);
            if (index != null) {
              onStrokeStart(index);
              onStrokeEnd();
            }
          },
          onPanStart: (details) {
            final index = _indexFromLocalPosition(details.localPosition);
            if (index != null) {
              onStrokeStart(index);
            }
          },
          onPanUpdate: (details) {
            final index = _indexFromLocalPosition(details.localPosition);
            if (index != null) {
              onCellDrag(index);
            }
          },
          onPanEnd: (_) => onStrokeEnd(),
          onPanCancel: onStrokeEnd,
          child: SizedBox(
            width: width * _cellSize,
            height: height * _cellSize,
            child: GridView.builder(
              itemCount: state.cells.length,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: width,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final cell = state.cells[index];
                final isSelected = state.selectedCellIndex == index;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected ? Colors.indigo : Colors.black26,
                      width: isSelected ? 2 : 1,
                    ),
                    color: cell.paintColor ?? Colors.white,
                  ),
                  child: Stack(
                    children: [
                      if (cell.isInactive) const _InactiveOverlay(),
                      if (cell.hasStartMarker) const _StartMarkerOverlay(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  int? _indexFromLocalPosition(Offset position) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;
    if (position.dx < 0 || position.dy < 0) {
      return null;
    }

    final column = position.dx ~/ _cellSize;
    final row = position.dy ~/ _cellSize;
    if (column < 0 || column >= width || row < 0 || row >= height) {
      return null;
    }

    return (row * width) + column;
  }
}

class _InactiveOverlay extends StatelessWidget {
  const _InactiveOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black.withValues(alpha: 0.12)),
        CustomPaint(painter: _CrossPainter()),
      ],
    );
  }
}

class _StartMarkerOverlay extends StatelessWidget {
  const _StartMarkerOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black87, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const inset = 10.0;
    canvas
      ..drawLine(
        const Offset(inset, inset),
        Offset(size.width - inset, size.height - inset),
        paint,
      )
      ..drawLine(
        Offset(size.width - inset, inset),
        Offset(inset, size.height - inset),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
