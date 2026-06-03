import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditorGridView extends StatefulWidget {
  const EditorGridView({
    super.key,
    required this.state,
    required this.onStrokeStart,
    required this.onCellDrag,
    required this.onStrokeEnd,
    required this.onEraseStrokeStart,
    required this.onEraseCellDrag,
    required this.onEraseStrokeEnd,
  });

  final EditorState state;
  final ValueChanged<int> onStrokeStart;
  final ValueChanged<int> onCellDrag;
  final VoidCallback onStrokeEnd;
  final ValueChanged<int> onEraseStrokeStart;
  final ValueChanged<int> onEraseCellDrag;
  final VoidCallback onEraseStrokeEnd;

  @override
  State<EditorGridView> createState() => _EditorGridViewState();
}

class _EditorGridViewState extends State<EditorGridView> {
  static const double _cellSize = 48;
  static const double _minZoom = 0.2;
  static const double _maxZoom = 2.2;
  static const double _wheelZoomStep = 0.0015;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewportSize = Size.zero;
  String? _lastGridKey;

  bool _isPaintingStroke = false;
  bool _isErasingStroke = false;
  int? _erasePointerId;
  bool _isModifiedPanStroke = false;
  int? _panPointerId;
  Offset _panLastViewportPosition = Offset.zero;
  bool _isViewportGesture = false;
  double _gestureStartScale = 1;
  Offset _gestureStartSceneFocal = Offset.zero;
  double _panZoomStartScale = 1;
  Offset _panZoomStartSceneFocal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleClampIfNeeded(viewportSize);

        return ClipRect(
          child: SizedBox.expand(
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              onPointerSignal: _handlePointerSignal,
              onPointerPanZoomStart: _handlePointerPanZoomStart,
              onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (_) {},
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GridPainter(
                    state: widget.state,
                    cellSize: _cellSize,
                    scale: _scale,
                    offset: _offset,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }

    final factor = (1 - event.scrollDelta.dy * _wheelZoomStep).clamp(
      0.85,
      1.15,
    );
    _zoomAt(event.localPosition, _scale * factor);
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _endPaintStrokeIfNeeded();
    _endEraseStrokeIfNeeded();
    _endModifiedPanIfNeeded();
    _panZoomStartScale = _scale;
    _panZoomStartSceneFocal = _scenePositionFromViewport(event.localPosition);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isPanModifierPressed() && _hasMousePaintOrEraseButton(event.buttons)) {
      _endPaintStrokeIfNeeded();
      _endEraseStrokeIfNeeded();
      _isModifiedPanStroke = true;
      _panPointerId = event.pointer;
      _panLastViewportPosition = event.localPosition;
      return;
    }

    if (!_hasSecondaryButton(event.buttons)) {
      return;
    }

    final index = _indexFromViewportPosition(event.localPosition);
    if (index == null) {
      return;
    }

    _erasePointerId = event.pointer;
    _isErasingStroke = true;
    _endPaintStrokeIfNeeded();
    widget.onEraseStrokeStart(index);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isModifiedPanStroke && event.pointer == _panPointerId) {
      if (!_hasMousePaintOrEraseButton(event.buttons)) {
        _endModifiedPanIfNeeded();
        return;
      }

      final delta = event.localPosition - _panLastViewportPosition;
      _panLastViewportPosition = event.localPosition;
      if (delta == Offset.zero) {
        return;
      }

      setState(() {
        _offset = _clampOffset(_offset + delta, _scale, _viewportSize);
      });
      return;
    }

    if (!_isErasingStroke || event.pointer != _erasePointerId) {
      return;
    }

    final index = _indexFromViewportPosition(event.localPosition);
    if (index != null) {
      widget.onEraseCellDrag(index);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == _panPointerId) {
      _endModifiedPanIfNeeded();
      return;
    }

    if (event.pointer != _erasePointerId) {
      return;
    }
    _endEraseStrokeIfNeeded();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _panPointerId) {
      _endModifiedPanIfNeeded();
      return;
    }

    if (event.pointer != _erasePointerId) {
      return;
    }
    _endEraseStrokeIfNeeded();
  }

  bool _hasSecondaryButton(int buttons) => buttons & kSecondaryMouseButton != 0;
  bool _hasPrimaryButton(int buttons) => buttons & kPrimaryMouseButton != 0;
  bool _hasMousePaintOrEraseButton(int buttons) =>
      _hasPrimaryButton(buttons) || _hasSecondaryButton(buttons);

  bool _isPanModifierPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final nextScale = (_panZoomStartScale * event.scale).clamp(
      _minZoom,
      _maxZoom,
    );
    final nextOffset =
        event.localPosition - _panZoomStartSceneFocal * nextScale + event.pan;

    setState(() {
      _scale = nextScale;
      _offset = _clampOffset(nextOffset, _scale, _viewportSize);
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (_isErasingStroke || _isModifiedPanStroke) {
      _endPaintStrokeIfNeeded();
      return;
    }

    _gestureStartScale = _scale;
    _gestureStartSceneFocal = _scenePositionFromViewport(
      details.localFocalPoint,
    );
    _isViewportGesture = details.pointerCount > 1;

    if (_isViewportGesture) {
      _endPaintStrokeIfNeeded();
      return;
    }

    final index = _indexFromViewportPosition(details.localFocalPoint);
    if (index != null) {
      _isPaintingStroke = true;
      widget.onStrokeStart(index);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_isErasingStroke || _isModifiedPanStroke) {
      _endPaintStrokeIfNeeded();
      return;
    }

    if (details.pointerCount > 1 || _isViewportGesture) {
      _isViewportGesture = true;
      _endPaintStrokeIfNeeded();

      final nextScale = (_gestureStartScale * details.scale).clamp(
        _minZoom,
        _maxZoom,
      );
      final nextOffset =
          details.localFocalPoint - _gestureStartSceneFocal * nextScale;

      setState(() {
        _scale = nextScale;
        _offset = _clampOffset(nextOffset, _scale, _viewportSize);
      });
      return;
    }

    final index = _indexFromViewportPosition(details.localFocalPoint);
    if (index != null) {
      if (!_isPaintingStroke) {
        _isPaintingStroke = true;
        widget.onStrokeStart(index);
      } else {
        widget.onCellDrag(index);
      }
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_isErasingStroke || _isModifiedPanStroke) {
      return;
    }
    _endPaintStrokeIfNeeded();
    _isViewportGesture = false;
  }

  void _zoomAt(Offset viewportFocalPoint, double targetScale) {
    final nextScale = targetScale.clamp(_minZoom, _maxZoom);
    final sceneFocalPoint = _scenePositionFromViewport(viewportFocalPoint);
    final nextOffset = viewportFocalPoint - sceneFocalPoint * nextScale;

    setState(() {
      _scale = nextScale;
      _offset = _clampOffset(nextOffset, _scale, _viewportSize);
    });
  }

  void _endPaintStrokeIfNeeded() {
    if (!_isPaintingStroke) {
      return;
    }

    widget.onStrokeEnd();
    _isPaintingStroke = false;
  }

  void _endEraseStrokeIfNeeded() {
    if (!_isErasingStroke) {
      return;
    }

    widget.onEraseStrokeEnd();
    _isErasingStroke = false;
    _erasePointerId = null;
  }

  void _endModifiedPanIfNeeded() {
    if (!_isModifiedPanStroke) {
      return;
    }

    _isModifiedPanStroke = false;
    _panPointerId = null;
  }

  void _scheduleClampIfNeeded(Size viewportSize) {
    _viewportSize = viewportSize;

    final gridKey =
        '${widget.state.gridSize.width}x${widget.state.gridSize.height}';
    final isNewGrid = _lastGridKey != gridKey;
    _lastGridKey = gridKey;

    final targetOffset = isNewGrid
        ? _centeredOffset(_scale, viewportSize)
        : _clampOffset(_offset, _scale, viewportSize);
    if (targetOffset == _offset) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _offset = targetOffset;
      });
    });
  }

  Offset _scenePositionFromViewport(Offset viewportPosition) {
    return (viewportPosition - _offset) / _scale;
  }

  Offset _centeredOffset(double scale, Size viewportSize) {
    final contentWidth = widget.state.gridSize.width * _cellSize * scale;
    final contentHeight = widget.state.gridSize.height * _cellSize * scale;
    return Offset(
      (viewportSize.width - contentWidth) / 2,
      (viewportSize.height - contentHeight) / 2,
    );
  }

  Offset _clampOffset(Offset offset, double scale, Size viewportSize) {
    final contentWidth = widget.state.gridSize.width * _cellSize * scale;
    final contentHeight = widget.state.gridSize.height * _cellSize * scale;

    return Offset(
      _clampAxisOffset(
        offset: offset.dx,
        contentExtent: contentWidth,
        viewportExtent: viewportSize.width,
      ),
      _clampAxisOffset(
        offset: offset.dy,
        contentExtent: contentHeight,
        viewportExtent: viewportSize.height,
      ),
    );
  }

  // Center-based clamp inspired by the old game camera: the viewport center
  // (in scene coordinates) must stay within the board extent. This lets the
  // board overshift so empty space shows near an edge, but it can never move
  // so far that it leaves the screen.
  double _clampAxisOffset({
    required double offset,
    required double contentExtent,
    required double viewportExtent,
  }) {
    final maxOffset = viewportExtent / 2;
    final minOffset = viewportExtent / 2 - contentExtent;
    return offset.clamp(minOffset, maxOffset);
  }

  int? _indexFromViewportPosition(Offset position) {
    final scenePosition = _scenePositionFromViewport(position);
    final width = widget.state.gridSize.width;
    final height = widget.state.gridSize.height;
    if (scenePosition.dx < 0 || scenePosition.dy < 0) {
      return null;
    }

    final column = scenePosition.dx ~/ _cellSize;
    final row = scenePosition.dy ~/ _cellSize;
    if (column < 0 || column >= width || row < 0 || row >= height) {
      return null;
    }

    return (row * width) + column;
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.state,
    required this.cellSize,
    required this.scale,
    required this.offset,
  });

  final EditorState state;
  final double cellSize;
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final width = state.gridSize.width;
    final height = state.gridSize.height;

    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    final boardRect = Rect.fromLTWH(0, 0, width * cellSize, height * cellSize);
    canvas.drawRect(boardRect, Paint()..color = Colors.white);

    final visibleLeft = -offset.dx / scale;
    final visibleTop = -offset.dy / scale;
    final visibleRight = (size.width - offset.dx) / scale;
    final visibleBottom = (size.height - offset.dy) / scale;

    final firstColumn = (visibleLeft / cellSize).floor().clamp(0, width - 1);
    final lastColumn = (visibleRight / cellSize).ceil().clamp(0, width);
    final firstRow = (visibleTop / cellSize).floor().clamp(0, height - 1);
    final lastRow = (visibleBottom / cellSize).ceil().clamp(0, height);

    final inactiveFillPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12);
    final crossPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final markerFillPaint = Paint()..color = Colors.white;
    final markerBorderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final gridLinePaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final selectedPaint = Paint()
      ..color = Colors.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var row = firstRow; row < lastRow; row += 1) {
      for (var column = firstColumn; column < lastColumn; column += 1) {
        final index = (row * width) + column;
        final cell = state.cells[index];
        final rect = Rect.fromLTWH(
          column * cellSize,
          row * cellSize,
          cellSize,
          cellSize,
        );

        if (cell.paintColor != null) {
          canvas.drawRect(rect, Paint()..color = cell.paintColor!);
        }

        if (cell.isInactive) {
          canvas.drawRect(rect, inactiveFillPaint);
          const inset = 10.0;
          canvas
            ..drawLine(
              rect.topLeft + const Offset(inset, inset),
              rect.bottomRight - const Offset(inset, inset),
              crossPaint,
            )
            ..drawLine(
              rect.topRight + const Offset(-inset, inset),
              rect.bottomLeft + const Offset(inset, -inset),
              crossPaint,
            );
        }

        if (cell.hasStartMarker) {
          canvas
            ..drawCircle(rect.center, 9, markerFillPaint)
            ..drawCircle(rect.center, 9, markerBorderPaint);
        }

        final isSelected = state.selectedCellIndex == index;
        canvas.drawRect(rect, isSelected ? selectedPaint : gridLinePaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset;
  }
}
