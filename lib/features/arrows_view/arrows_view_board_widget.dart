import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_painter.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';

class ArrowsViewBoardWidget extends StatefulWidget {
  const ArrowsViewBoardWidget({super.key, required this.model});

  final ArrowsViewRuntimeModel model;

  @override
  State<ArrowsViewBoardWidget> createState() => _ArrowsViewBoardWidgetState();
}

class _ArrowsViewBoardWidgetState extends State<ArrowsViewBoardWidget> {
  static const double _minZoom = 0.2;
  static const double _maxZoom = 2.2;
  static const double _wheelZoomStep = 0.0015;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewportSize = Size.zero;
  String? _lastModelKey;

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
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleClampIfNeeded(viewport);
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
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ArrowsViewBoardPainter(
                      model: widget.model,
                      scale: _scale,
                      offset: _offset,
                    ),
                    size: Size.infinite,
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
    _endModifiedPanIfNeeded();
    _panZoomStartScale = _scale;
    _panZoomStartSceneFocal = _scenePositionFromViewport(event.localPosition);
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
    _gestureStartScale = _scale;
    _gestureStartSceneFocal = _scenePositionFromViewport(
      details.localFocalPoint,
    );
    _isViewportGesture = details.pointerCount > 1;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || _isViewportGesture) {
      _isViewportGesture = true;
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
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isViewportGesture = false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isPanModifierPressed() && _hasMousePaintOrEraseButton(event.buttons)) {
      _isModifiedPanStroke = true;
      _panPointerId = event.pointer;
      _panLastViewportPosition = event.localPosition;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isModifiedPanStroke || event.pointer != _panPointerId) {
      return;
    }
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
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == _panPointerId) {
      _endModifiedPanIfNeeded();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _panPointerId) {
      _endModifiedPanIfNeeded();
    }
  }

  void _endModifiedPanIfNeeded() {
    if (!_isModifiedPanStroke) {
      return;
    }
    _isModifiedPanStroke = false;
    _panPointerId = null;
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

  void _zoomAt(Offset viewportFocalPoint, double targetScale) {
    final nextScale = targetScale.clamp(_minZoom, _maxZoom);
    final sceneFocalPoint = _scenePositionFromViewport(viewportFocalPoint);
    final nextOffset = viewportFocalPoint - sceneFocalPoint * nextScale;
    setState(() {
      _scale = nextScale;
      _offset = _clampOffset(nextOffset, _scale, _viewportSize);
    });
  }

  void _scheduleClampIfNeeded(Size viewport) {
    _viewportSize = viewport;
    final modelKey = '${widget.model.width}x${widget.model.height}';
    final isNewModel = _lastModelKey != modelKey;
    _lastModelKey = modelKey;
    final targetOffset = isNewModel
        ? Offset.zero
        : _clampOffset(_offset, _scale, _viewportSize);
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

  Offset _clampOffset(Offset offset, double scale, Size viewportSize) {
    final layout = ArrowsViewBoardLayout.compute(
      size: viewportSize,
      width: widget.model.width,
      height: widget.model.height,
    );
    return Offset(
      _clampAxisOffset(
        offset: offset.dx,
        scale: scale,
        viewportExtent: viewportSize.width,
        minScene: layout.boardBounds.left,
        maxScene: layout.boardBounds.right,
      ),
      _clampAxisOffset(
        offset: offset.dy,
        scale: scale,
        viewportExtent: viewportSize.height,
        minScene: layout.boardBounds.top,
        maxScene: layout.boardBounds.bottom,
      ),
    );
  }

  double _clampAxisOffset({
    required double offset,
    required double scale,
    required double viewportExtent,
    required double minScene,
    required double maxScene,
  }) {
    final maxOffset = viewportExtent / 2 - minScene * scale;
    final minOffset = viewportExtent / 2 - maxScene * scale;
    return offset.clamp(minOffset, maxOffset);
  }
}
