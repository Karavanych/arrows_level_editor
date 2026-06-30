import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';

class ArrowsViewRenderSettings {
  const ArrowsViewRenderSettings({
    required this.isColored,
    required this.thicknessScale,
    required this.backgroundColor,
  });

  final bool isColored;
  final double thicknessScale;
  final Color backgroundColor;
}

class ArrowsViewBoardPainter extends CustomPainter {
  const ArrowsViewBoardPainter({
    required this.model,
    required this.scale,
    required this.offset,
    required this.settings,
  });

  static const double _outerPadding = 24;
  static const double _maxPointSpacing = 84;
  static const double _minPointSpacing = 28;
  static const double _baseLineWidth = 8.5;
  static const double _baseSupportRadius = 3.2;
  static const double _baseArrowLength = _baseLineWidth * 2.4;
  static const double _baseArrowHalfWidth = _baseLineWidth * 1.1;
  static const double _baseArrowTipForwardOffset = _baseLineWidth * 1.3;
  static const double _inactiveCellScale = 0.9;
  static const bool _showInactiveCells = false;
  static const bool _showSupportPoints = false;
  static const double _exportPadding = 24;

  final ArrowsViewRuntimeModel model;
  final double scale;
  final Offset offset;
  final ArrowsViewRenderSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = settings.backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);
    if (model.width <= 0 || model.height <= 0) {
      return;
    }

    final layout = ArrowsViewBoardLayout.compute(
      size: size,
      width: model.width,
      height: model.height,
    );

    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    if (_showInactiveCells) {
      _paintInactiveCells(canvas, layout);
    }
    _paintPaths(canvas, layout);
    if (_showSupportPoints) {
      _paintSupportPoints(canvas, layout);
    }
    canvas.restore();
  }

  static void paintForExport({
    required Canvas canvas,
    required Size size,
    required ArrowsViewRuntimeModel model,
    required ArrowsViewRenderSettings settings,
  }) {
    final painter = ArrowsViewBoardPainter(
      model: model,
      scale: 1,
      offset: Offset.zero,
      settings: settings,
    );
    final bgPaint = Paint()..color = settings.backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);
    if (model.width <= 0 || model.height <= 0 || model.paths.isEmpty) {
      return;
    }

    final innerRect = Rect.fromLTWH(
      _exportPadding,
      _exportPadding,
      math.max(1, size.width - _exportPadding * 2),
      math.max(1, size.height - _exportPadding * 2),
    );
    final layout = ArrowsViewBoardLayout.exportCanonical(
      width: model.width,
      height: model.height,
    );
    final bounds = painter._computeArtworkBounds(layout);
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
      return;
    }

    final fitScale = math.min(
      innerRect.width / bounds.width,
      innerRect.height / bounds.height,
    );
    final targetCenter = innerRect.center;
    final sourceCenter = bounds.center;
    final dx = targetCenter.dx - sourceCenter.dx * fitScale;
    final dy = targetCenter.dy - sourceCenter.dy * fitScale;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(fitScale);
    painter._paintPaths(canvas, layout);
    canvas.restore();
  }

  void _paintInactiveCells(Canvas canvas, ArrowsViewBoardLayout layout) {
    final inactivePaint = Paint()..color = const Color(0xFFFFFFFF);
    final borderPaint = Paint()
      ..color = const Color(0x11000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, layout.pointSpacing * 0.015);
    final side = layout.pointSpacing * _inactiveCellScale;

    for (var index = 0; index < model.activeMask.length; index += 1) {
      if (model.activeMask[index]) {
        continue;
      }
      final x = index % model.width;
      final y = index ~/ model.width;
      final center = layout.pointToCanvas(x.toDouble(), y.toDouble());
      final rect = Rect.fromCenter(center: center, width: side, height: side);
      canvas.drawRect(rect, inactivePaint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _paintPaths(Canvas canvas, ArrowsViewBoardLayout layout) {
    final strokeWidth =
        _scaled(_baseLineWidth, layout) * settings.thicknessScale;
    final arrowLength =
        _scaled(_baseArrowLength, layout) * settings.thicknessScale;
    final arrowHalfWidth =
        _scaled(_baseArrowHalfWidth, layout) * settings.thicknessScale;
    final arrowTipForwardOffset =
        _scaled(_baseArrowTipForwardOffset, layout) * settings.thicknessScale;

    for (final path in model.paths) {
      if (path.points.length < 2) {
        continue;
      }
      final color = settings.isColored
          ? Color(path.colorValue)
          : const Color(0xFF222222);
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final linePath = Path();
      final first = layout.pointToCanvas(
        path.points.first.dx,
        path.points.first.dy,
      );
      linePath.moveTo(first.dx, first.dy);
      for (var i = 1; i < path.points.length; i += 1) {
        final next = layout.pointToCanvas(path.points[i].dx, path.points[i].dy);
        linePath.lineTo(next.dx, next.dy);
      }
      canvas.drawPath(linePath, linePaint);

      final headCenter = layout.pointToCanvas(
        path.headPose.position.dx,
        path.headPose.position.dy,
      );
      final direction = _normalize(path.headPose.direction);
      final tip = headCenter + direction * arrowTipForwardOffset;
      final baseCenter = tip - direction * arrowLength;
      final perpendicular = Offset(-direction.dy, direction.dx);
      final left = baseCenter + perpendicular * arrowHalfWidth;
      final right = baseCenter - perpendicular * arrowHalfWidth;

      final headPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(headPath, Paint()..color = color);
    }
  }

  void _paintSupportPoints(Canvas canvas, ArrowsViewBoardLayout layout) {
    final radius = _scaled(_baseSupportRadius, layout);
    final supportPaint = Paint()..color = const Color(0xFF111111);
    for (final point in model.supportPoints) {
      canvas.drawCircle(
        layout.pointToCanvas(point.dx, point.dy),
        radius,
        supportPaint,
      );
    }
  }

  Offset _normalize(Offset vector) {
    final length = vector.distance;
    if (length <= 0.0001) {
      return const Offset(1, 0);
    }
    return Offset(vector.dx / length, vector.dy / length);
  }

  double _scaled(double base, ArrowsViewBoardLayout layout) {
    return base * (layout.pointSpacing / _maxPointSpacing).clamp(0.6, 1.4);
  }

  @override
  bool shouldRepaint(covariant ArrowsViewBoardPainter oldDelegate) {
    return oldDelegate.model != model ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.settings.isColored != settings.isColored ||
        oldDelegate.settings.thicknessScale != settings.thicknessScale ||
        oldDelegate.settings.backgroundColor != settings.backgroundColor;
  }

  Rect? _computeArtworkBounds(ArrowsViewBoardLayout layout) {
    final strokeWidth =
        _scaled(_baseLineWidth, layout) * settings.thicknessScale;
    final arrowLength =
        _scaled(_baseArrowLength, layout) * settings.thicknessScale;
    final arrowHalfWidth =
        _scaled(_baseArrowHalfWidth, layout) * settings.thicknessScale;
    final arrowTipForwardOffset =
        _scaled(_baseArrowTipForwardOffset, layout) * settings.thicknessScale;
    final halfStroke = strokeWidth * 0.5;

    Rect? bounds;
    for (final path in model.paths) {
      if (path.points.length < 2) {
        continue;
      }
      for (var i = 1; i < path.points.length; i += 1) {
        final start = layout.pointToCanvas(
          path.points[i - 1].dx,
          path.points[i - 1].dy,
        );
        final end = layout.pointToCanvas(path.points[i].dx, path.points[i].dy);
        final segmentRect = Rect.fromLTRB(
          math.min(start.dx, end.dx) - halfStroke,
          math.min(start.dy, end.dy) - halfStroke,
          math.max(start.dx, end.dx) + halfStroke,
          math.max(start.dy, end.dy) + halfStroke,
        );
        bounds = bounds == null
            ? segmentRect
            : bounds.expandToInclude(segmentRect);
      }

      final headCenter = layout.pointToCanvas(
        path.headPose.position.dx,
        path.headPose.position.dy,
      );
      final direction = _normalize(path.headPose.direction);
      final tip = headCenter + direction * arrowTipForwardOffset;
      final baseCenter = tip - direction * arrowLength;
      final perpendicular = Offset(-direction.dy, direction.dx);
      final left = baseCenter + perpendicular * arrowHalfWidth;
      final right = baseCenter - perpendicular * arrowHalfWidth;
      var headBounds = Rect.fromPoints(
        tip,
        left,
      ).expandToInclude(Rect.fromPoints(tip, right));
      headBounds = headBounds.inflate(halfStroke * 0.2);
      bounds = bounds == null ? headBounds : bounds.expandToInclude(headBounds);
    }
    return bounds;
  }
}

class ArrowsViewBoardLayout {
  const ArrowsViewBoardLayout({
    required this.origin,
    required this.pointSpacing,
    required this.boardBounds,
  });

  final Offset origin;
  final double pointSpacing;
  final Rect boardBounds;

  factory ArrowsViewBoardLayout.compute({
    required Size size,
    required int width,
    required int height,
  }) {
    final maxXSpan = math.max(0, width - 1).toDouble();
    final maxYSpan = math.max(0, height - 1).toDouble();
    final availableWidth = math.max(
      1.0,
      size.width - ArrowsViewBoardPainter._outerPadding * 2,
    );
    final availableHeight = math.max(
      1.0,
      size.height - ArrowsViewBoardPainter._outerPadding * 2,
    );

    final spacingByWidth = maxXSpan == 0
        ? ArrowsViewBoardPainter._maxPointSpacing
        : availableWidth / maxXSpan;
    final spacingByHeight = maxYSpan == 0
        ? ArrowsViewBoardPainter._maxPointSpacing
        : availableHeight / maxYSpan;
    final spacing = math
        .min(spacingByWidth, spacingByHeight)
        .clamp(
          ArrowsViewBoardPainter._minPointSpacing,
          ArrowsViewBoardPainter._maxPointSpacing,
        );

    final boardWidth = maxXSpan * spacing;
    final boardHeight = maxYSpan * spacing;
    final origin = Offset(
      (size.width - boardWidth) * 0.5,
      (size.height - boardHeight) * 0.5,
    );
    return ArrowsViewBoardLayout(
      origin: origin,
      pointSpacing: spacing,
      boardBounds: Rect.fromLTWH(origin.dx, origin.dy, boardWidth, boardHeight),
    );
  }

  Offset pointToCanvas(double gridX, double gridY) {
    return Offset(
      origin.dx + gridX * pointSpacing,
      origin.dy + gridY * pointSpacing,
    );
  }

  factory ArrowsViewBoardLayout.exportCanonical({
    required int width,
    required int height,
  }) {
    final pointSpacing = ArrowsViewBoardPainter._maxPointSpacing;
    final boardWidth = math.max(0, width - 1).toDouble() * pointSpacing;
    final boardHeight = math.max(0, height - 1).toDouble() * pointSpacing;
    final origin = Offset(-boardWidth * 0.5, -boardHeight * 0.5);
    return ArrowsViewBoardLayout(
      origin: origin,
      pointSpacing: pointSpacing,
      boardBounds: Rect.fromLTWH(origin.dx, origin.dy, boardWidth, boardHeight),
    );
  }
}
