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

class ArrowsViewAnimationFrame {
  const ArrowsViewAnimationFrame({
    required this.pendingPathIndices,
    required this.launchedAt,
    required this.elapsed,
    required this.flightDuration,
    required this.flightSpeed,
  });

  final Set<int> pendingPathIndices;
  final Map<int, Duration> launchedAt;
  final Duration elapsed;
  final Duration flightDuration;
  final double flightSpeed;
}

class ArrowsViewBoardPainter extends CustomPainter {
  const ArrowsViewBoardPainter({
    required this.model,
    required this.scale,
    required this.offset,
    required this.settings,
    this.animationFrame,
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
  final ArrowsViewAnimationFrame? animationFrame;

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
    ArrowsViewAnimationFrame? animationFrame,
  }) {
    final painter = ArrowsViewBoardPainter(
      model: model,
      scale: 1,
      offset: Offset.zero,
      settings: settings,
      animationFrame: animationFrame,
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

    for (var pathIndex = 0; pathIndex < model.paths.length; pathIndex += 1) {
      final path = model.paths[pathIndex];
      if (path.points.length < 2) {
        continue;
      }
      final window = _animationWindowForPath(
        pathIndex: pathIndex,
        path: path,
        layout: layout,
        strokeWidth: strokeWidth,
        arrowLength: arrowLength,
        arrowTipForwardOffset: arrowTipForwardOffset,
      );
      if (window == null) {
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

      if (window.visiblePolyline.length < 2) {
        continue;
      }

      final linePath = Path()
        ..moveTo(
          window.visiblePolyline.first.dx,
          window.visiblePolyline.first.dy,
        );
      for (var i = 1; i < window.visiblePolyline.length; i += 1) {
        final next = window.visiblePolyline[i];
        linePath.lineTo(next.dx, next.dy);
      }
      canvas.drawPath(linePath, linePaint);

      final tip =
          window.headPosition + window.headDirection * arrowTipForwardOffset;
      final baseCenter = tip - window.headDirection * arrowLength;
      final perpendicular = Offset(
        -window.headDirection.dy,
        window.headDirection.dx,
      );
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
        oldDelegate.settings.backgroundColor != settings.backgroundColor ||
        oldDelegate.animationFrame != animationFrame;
  }

  _PathRenderWindow? _animationWindowForPath({
    required int pathIndex,
    required ArrowsViewRenderPath path,
    required ArrowsViewBoardLayout layout,
    required double strokeWidth,
    required double arrowLength,
    required double arrowTipForwardOffset,
  }) {
    final basePolyline = path.points
        .map((point) => layout.pointToCanvas(point.dx, point.dy))
        .toList(growable: true);
    if (basePolyline.length < 2) {
      return null;
    }
    final basePathLength = _polylineLength(basePolyline);
    if (basePathLength <= 0) {
      return null;
    }

    final direction = _normalize(path.headPose.direction);
    final head = basePolyline.last;
    final frame = animationFrame;
    if (frame == null || frame.pendingPathIndices.contains(pathIndex)) {
      return _PathRenderWindow(
        visiblePolyline: basePolyline,
        headPosition: head,
        headDirection: direction,
      );
    }

    final launchedAt = frame.launchedAt[pathIndex];
    if (launchedAt == null) {
      return null;
    }
    final flightMs = frame.flightDuration.inMilliseconds;
    if (flightMs <= 0) {
      return null;
    }
    final progress = ((frame.elapsed - launchedAt).inMilliseconds / flightMs)
        .toDouble();
    final effectiveProgress = (progress * frame.flightSpeed).clamp(0.0, 1.0);
    if (effectiveProgress >= 1.0) {
      return null;
    }

    final successTravelDistance = _successTravelDistance(
      head: head,
      direction: direction,
      bounds: layout.boardBounds,
      strokeWidth: strokeWidth,
      arrowLength: arrowLength,
      arrowTipForwardOffset: arrowTipForwardOffset,
    );
    final travel = successTravelDistance * effectiveProgress;
    final extendedPolyline = List<Offset>.from(basePolyline)
      ..add(head + direction * successTravelDistance);

    final windowStart = travel;
    final windowEnd = travel + basePathLength;
    final visiblePolyline = _visiblePolylineInRange(
      polyline: extendedPolyline,
      rangeStart: windowStart,
      rangeEnd: windowEnd,
    );
    if (visiblePolyline.length < 2) {
      return null;
    }
    final headPose = _samplePoseAtDistance(extendedPolyline, windowEnd);
    return _PathRenderWindow(
      visiblePolyline: visiblePolyline,
      headPosition: headPose.position,
      headDirection: headPose.direction,
    );
  }

  double _distanceToExitBounds(Offset start, Offset direction, Rect bounds) {
    if (direction.dx > 0.001) {
      return bounds.right - start.dx;
    }
    if (direction.dx < -0.001) {
      return start.dx - bounds.left;
    }
    if (direction.dy > 0.001) {
      return bounds.bottom - start.dy;
    }
    return start.dy - bounds.top;
  }

  double _successTravelDistance({
    required Offset head,
    required Offset direction,
    required Rect bounds,
    required double strokeWidth,
    required double arrowLength,
    required double arrowTipForwardOffset,
  }) {
    final distanceToBounds = _distanceToExitBounds(head, direction, bounds);
    return distanceToBounds +
        arrowLength +
        arrowTipForwardOffset +
        strokeWidth +
        _maxPointSpacing * 1.2;
  }

  double _polylineLength(List<Offset> polyline) {
    var length = 0.0;
    for (var i = 1; i < polyline.length; i += 1) {
      length += (polyline[i] - polyline[i - 1]).distance;
    }
    return length;
  }

  List<Offset> _visiblePolylineInRange({
    required List<Offset> polyline,
    required double rangeStart,
    required double rangeEnd,
  }) {
    final result = <Offset>[];
    var accumulated = 0.0;
    for (var i = 1; i < polyline.length; i += 1) {
      final a = polyline[i - 1];
      final b = polyline[i];
      final segmentLength = (b - a).distance;
      if (segmentLength <= 0.0001) {
        continue;
      }
      final segmentStart = accumulated;
      final segmentEnd = accumulated + segmentLength;
      final visibleStart = math.max(segmentStart, rangeStart);
      final visibleEnd = math.min(segmentEnd, rangeEnd);
      if (visibleEnd > visibleStart) {
        final t0 = (visibleStart - segmentStart) / segmentLength;
        final t1 = (visibleEnd - segmentStart) / segmentLength;
        final p0 = Offset.lerp(a, b, t0)!;
        final p1 = Offset.lerp(a, b, t1)!;
        if (result.isEmpty || (result.last - p0).distance > 0.001) {
          result.add(p0);
        }
        if ((result.last - p1).distance > 0.001) {
          result.add(p1);
        }
      }
      accumulated = segmentEnd;
    }
    return result;
  }

  _SampledPose _samplePoseAtDistance(List<Offset> polyline, double distance) {
    if (polyline.length < 2) {
      return const _SampledPose(position: Offset.zero, direction: Offset(1, 0));
    }
    if (distance <= 0) {
      final direction = _normalize(polyline[1] - polyline[0]);
      return _SampledPose(position: polyline.first, direction: direction);
    }

    var accumulated = 0.0;
    for (var i = 1; i < polyline.length; i += 1) {
      final a = polyline[i - 1];
      final b = polyline[i];
      final segment = b - a;
      final segmentLength = segment.distance;
      if (segmentLength <= 0.0001) {
        continue;
      }
      final nextAccumulated = accumulated + segmentLength;
      if (distance <= nextAccumulated) {
        final t = ((distance - accumulated) / segmentLength).clamp(0.0, 1.0);
        final position = Offset.lerp(a, b, t)!;
        final direction = _normalize(segment);
        return _SampledPose(position: position, direction: direction);
      }
      accumulated = nextAccumulated;
    }

    final last = polyline.last;
    final prev = polyline[polyline.length - 2];
    return _SampledPose(position: last, direction: _normalize(last - prev));
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

class _PathRenderWindow {
  const _PathRenderWindow({
    required this.visiblePolyline,
    required this.headPosition,
    required this.headDirection,
  });

  final List<Offset> visiblePolyline;
  final Offset headPosition;
  final Offset headDirection;
}

class _SampledPose {
  const _SampledPose({required this.position, required this.direction});

  final Offset position;
  final Offset direction;
}
