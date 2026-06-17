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
    required this.onEditorInteractionStart,
    required this.onColorPick,
    this.isPaintColorPickEnabled = true,
    this.isLineModeEnabled = false,
    this.highlightedErrorCells = const {},
    this.highlightedErrorColor = Colors.redAccent,
  });

  final EditorState state;
  final ValueChanged<int> onStrokeStart;
  final ValueChanged<int> onCellDrag;
  final VoidCallback onStrokeEnd;
  final ValueChanged<int> onEraseStrokeStart;
  final ValueChanged<int> onEraseCellDrag;
  final VoidCallback onEraseStrokeEnd;
  final VoidCallback onEditorInteractionStart;
  final ValueChanged<Color> onColorPick;
  final bool isPaintColorPickEnabled;
  final bool isLineModeEnabled;
  final Set<int> highlightedErrorCells;
  final Color highlightedErrorColor;

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
  int? _primaryPointerId;
  bool _isPendingColorPick = false;
  int? _pendingColorPickIndex;
  int? _primaryLastIndex;
  bool _primaryMovedAcrossCells = false;
  bool _isModifiedPanStroke = false;
  int? _panPointerId;
  Offset _panLastViewportPosition = Offset.zero;
  bool _isViewportGesture = false;
  double _gestureStartScale = 1;
  Offset _gestureStartSceneFocal = Offset.zero;
  double _panZoomStartScale = 1;
  Offset _panZoomStartSceneFocal = Offset.zero;
  int? _lineStartIndex;
  int? _lineEndIndex;

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
                    highlightedErrorCells: widget.highlightedErrorCells,
                    highlightedErrorColor: widget.highlightedErrorColor,
                    linePreviewIndices: _currentLinePreviewIndices(),
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
    widget.onEditorInteractionStart();

    if (_isPanModifierPressed() && _hasMousePaintOrEraseButton(event.buttons)) {
      _endPaintStrokeIfNeeded();
      _endEraseStrokeIfNeeded();
      _isModifiedPanStroke = true;
      _panPointerId = event.pointer;
      _panLastViewportPosition = event.localPosition;
      return;
    }

    if (!_hasSecondaryButton(event.buttons)) {
      if (_hasPrimaryButton(event.buttons)) {
        _primaryPointerId = event.pointer;
        _primaryLastIndex = _indexFromViewportPosition(event.localPosition);
        _primaryMovedAcrossCells = false;

        final canPickFromIndex = _primaryLastIndex;
        if (canPickFromIndex != null &&
            _canPickColorFromCell(canPickFromIndex)) {
          _isPendingColorPick = true;
          _pendingColorPickIndex = canPickFromIndex;
        } else {
          _isPendingColorPick = false;
          _pendingColorPickIndex = null;
        }
      }
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
      if (event.pointer == _primaryPointerId) {
        final index = _indexFromViewportPosition(event.localPosition);
        if (index != _primaryLastIndex) {
          _primaryMovedAcrossCells = true;
          _primaryLastIndex = index;
          if (widget.isLineModeEnabled &&
              _isPaintingStroke &&
              _lineStartIndex != null &&
              index != null) {
            setState(() {
              _lineEndIndex = index;
            });
          }
        }
      }
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
      if (event.pointer == _primaryPointerId) {
        if (widget.isLineModeEnabled && _isPaintingStroke && _lineStartIndex != null) {
          final upIndex = _indexFromViewportPosition(event.localPosition);
          if (upIndex != null) {
            _lineEndIndex = upIndex;
          }
          _applyLineStrokeIfNeeded();
        }
        final upIndex = _indexFromViewportPosition(event.localPosition);
        final isTrueClick =
            !_primaryMovedAcrossCells &&
            _isPendingColorPick &&
            _pendingColorPickIndex != null &&
            upIndex == _pendingColorPickIndex;
        if (isTrueClick) {
          final cell = widget.state.cells[_pendingColorPickIndex!];
          final color = cell.paintColor;
          if (color != null && !cell.isInactive) {
            widget.onColorPick(color);
          }
        }
        _resetPrimaryPointerState();
      }
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
      if (event.pointer == _primaryPointerId) {
        _resetPrimaryPointerState();
      }
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
      _isPendingColorPick = false;
      _pendingColorPickIndex = null;
      return;
    }

    if (_isPendingColorPick) {
      return;
    }

    final index = _indexFromViewportPosition(details.localFocalPoint);
    if (index != null) {
      _isPaintingStroke = true;
      if (widget.isLineModeEnabled) {
        _lineStartIndex = index;
        _lineEndIndex = index;
      } else {
        widget.onStrokeStart(index);
      }
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_isErasingStroke || _isModifiedPanStroke) {
      _endPaintStrokeIfNeeded();
      return;
    }

    if (_isPendingColorPick) {
      final index = _indexFromViewportPosition(details.localFocalPoint);
      final pendingIndex = _pendingColorPickIndex;
      if (index != null && pendingIndex != null && index != pendingIndex) {
        _isPendingColorPick = false;
        _pendingColorPickIndex = null;
        _isPaintingStroke = true;
        if (widget.isLineModeEnabled) {
          _lineStartIndex = index;
          _lineEndIndex = index;
        } else {
          widget.onStrokeStart(index);
        }
      }
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
        if (widget.isLineModeEnabled) {
          _lineStartIndex = index;
          _lineEndIndex = index;
        } else {
          widget.onStrokeStart(index);
        }
      } else {
        if (widget.isLineModeEnabled) {
          setState(() {
            _lineEndIndex = index;
          });
        } else {
          widget.onCellDrag(index);
        }
      }
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_isErasingStroke || _isModifiedPanStroke) {
      return;
    }
    if (_isPendingColorPick) {
      return;
    }
    if (widget.isLineModeEnabled && _isPaintingStroke && _lineStartIndex != null) {
      _applyLineStrokeIfNeeded();
    }
    _endPaintStrokeIfNeeded();
    _isViewportGesture = false;
  }

  bool _canPickColorFromCell(int index) {
    if (!widget.isPaintColorPickEnabled) {
      return false;
    }
    if (widget.state.selectedTool != EditorTool.paint) {
      return false;
    }
    final cell = widget.state.cells[index];
    return cell.paintColor != null && !cell.isInactive;
  }

  void _resetPrimaryPointerState() {
    _primaryPointerId = null;
    _primaryLastIndex = null;
    _primaryMovedAcrossCells = false;
    _isPendingColorPick = false;
    _pendingColorPickIndex = null;
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

    if (!widget.isLineModeEnabled) {
      widget.onStrokeEnd();
    }
    _isPaintingStroke = false;
    _lineStartIndex = null;
    _lineEndIndex = null;
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

  void _applyLineStrokeIfNeeded() {
    final start = _lineStartIndex;
    final end = _lineEndIndex;
    if (start == null || end == null) {
      return;
    }
    final segment = _buildAxisAlignedSegment(start, end);
    if (segment.isEmpty) {
      _lineStartIndex = null;
      _lineEndIndex = null;
      _isPaintingStroke = false;
      return;
    }

    widget.onStrokeStart(segment.first);
    for (var i = 1; i < segment.length; i += 1) {
      widget.onCellDrag(segment[i]);
    }
    widget.onStrokeEnd();

    setState(() {
      _lineStartIndex = null;
      _lineEndIndex = null;
      _isPaintingStroke = false;
    });
  }

  List<int> _buildAxisAlignedSegment(int start, int end) {
    final width = widget.state.gridSize.width;
    final startX = start % width;
    final startY = start ~/ width;
    final endX = end % width;
    final endY = end ~/ width;

    final dx = endX - startX;
    final dy = endY - startY;
    final horizontal = dx.abs() >= dy.abs();
    final result = <int>[];
    if (horizontal) {
      final targetX = endX;
      final step = targetX >= startX ? 1 : -1;
      for (var x = startX;; x += step) {
        result.add(startY * width + x);
        if (x == targetX) {
          break;
        }
      }
      return result;
    }

    final targetY = endY;
    final step = targetY >= startY ? 1 : -1;
    for (var y = startY;; y += step) {
      result.add(y * width + startX);
      if (y == targetY) {
        break;
      }
    }
    return result;
  }

  Set<int> _currentLinePreviewIndices() {
    if (!widget.isLineModeEnabled) {
      return const <int>{};
    }
    final start = _lineStartIndex;
    final end = _lineEndIndex;
    if (!_isPaintingStroke || start == null || end == null) {
      return const <int>{};
    }
    return _buildAxisAlignedSegment(start, end).toSet();
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.state,
    required this.cellSize,
    required this.scale,
    required this.offset,
    required this.highlightedErrorCells,
    required this.highlightedErrorColor,
    this.linePreviewIndices = const {},
  });

  final EditorState state;
  final double cellSize;
  final double scale;
  final Offset offset;
  final Set<int> highlightedErrorCells;
  final Color highlightedErrorColor;
  final Set<int> linePreviewIndices;

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
    final errorPaint = Paint()
      ..color = highlightedErrorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final linePreviewPaint = Paint()
      ..color = Colors.indigo.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

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
        if (linePreviewIndices.contains(index)) {
          canvas.drawRect(rect, linePreviewPaint);
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
          final center = rect.center;
          canvas
            ..drawCircle(center, 9, markerFillPaint)
            ..drawCircle(center, 9, markerBorderPaint);
          final arrowPaint = Paint()
            ..color = Colors.black87
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          final direction = cell.startDirection ?? StartDirection.right;
          final (vx, vy) = switch (direction) {
            StartDirection.right => (1.0, 0.0),
            StartDirection.down => (0.0, 1.0),
            StartDirection.left => (-1.0, 0.0),
            StartDirection.up => (0.0, -1.0),
          };
          final start = center + Offset(vx * 11, vy * 11);
          final end = start + Offset(vx * 10, vy * 10);
          canvas.drawLine(start, end, arrowPaint);
          final leftWing = Offset(
            end.dx - (vx * 4) - (vy * 3),
            end.dy - (vy * 4) + (vx * 3),
          );
          final rightWing = Offset(
            end.dx - (vx * 4) + (vy * 3),
            end.dy - (vy * 4) - (vx * 3),
          );
          canvas
            ..drawLine(end, leftWing, arrowPaint)
            ..drawLine(end, rightWing, arrowPaint);
        }

        final isSelected = state.selectedCellIndex == index;
        if (highlightedErrorCells.contains(index)) {
          canvas.drawRect(rect, errorPaint);
        } else {
          canvas.drawRect(rect, isSelected ? selectedPaint : gridLinePaint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.highlightedErrorCells != highlightedErrorCells ||
        oldDelegate.highlightedErrorColor != highlightedErrorColor ||
        oldDelegate.linePreviewIndices != linePreviewIndices;
  }
}
