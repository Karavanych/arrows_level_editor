import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';

class ArrowsViewBoardPainter extends CustomPainter {
  const ArrowsViewBoardPainter({required this.model});

  static const double _outerPadding = 24;
  static const double _maxPointSpacing = 84;
  static const double _minPointSpacing = 28;
  static const double _baseLineWidth = 8.5;
  static const double _baseSupportRadius = 3.2;
  static const double _baseArrowLength = _baseLineWidth * 2.4;
  static const double _baseArrowHalfWidth = _baseLineWidth * 1.1;
  static const double _inactiveCellScale = 0.9;

  final ArrowsViewRuntimeModel model;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF3F3F3);
    canvas.drawRect(Offset.zero & size, bgPaint);
    if (model.width <= 0 || model.height <= 0) {
      return;
    }

    final layout = _BoardLayout.compute(
      size: size,
      width: model.width,
      height: model.height,
    );

    _paintInactiveCells(canvas, layout);
    _paintPaths(canvas, layout);
    _paintSupportPoints(canvas, layout);
  }

  void _paintInactiveCells(Canvas canvas, _BoardLayout layout) {
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

  void _paintPaths(Canvas canvas, _BoardLayout layout) {
    final strokeWidth = _scaled(_baseLineWidth, layout);
    final arrowLength = _scaled(_baseArrowLength, layout);
    final arrowHalfWidth = _scaled(_baseArrowHalfWidth, layout);

    for (final path in model.paths) {
      if (path.points.length < 2) {
        continue;
      }
      final color = Color(path.colorValue);
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
      final tip = headCenter + direction * (strokeWidth * 0.55);
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

  void _paintSupportPoints(Canvas canvas, _BoardLayout layout) {
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

  double _scaled(double base, _BoardLayout layout) {
    return base * (layout.pointSpacing / _maxPointSpacing).clamp(0.6, 1.4);
  }

  @override
  bool shouldRepaint(covariant ArrowsViewBoardPainter oldDelegate) {
    return oldDelegate.model != model;
  }
}

class _BoardLayout {
  const _BoardLayout({required this.origin, required this.pointSpacing});

  final Offset origin;
  final double pointSpacing;

  factory _BoardLayout.compute({
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
    return _BoardLayout(origin: origin, pointSpacing: spacing);
  }

  Offset pointToCanvas(double gridX, double gridY) {
    return Offset(
      origin.dx + gridX * pointSpacing,
      origin.dy + gridY * pointSpacing,
    );
  }
}
