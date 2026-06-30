import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_painter.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_widget.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_export_service.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_level_snapshot.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_path_reconstructor.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_window_state_manager.dart';

class ArrowsViewWindowScreen extends StatefulWidget {
  const ArrowsViewWindowScreen({super.key, required this.snapshot});

  final ArrowsViewLevelSnapshot snapshot;

  @override
  State<ArrowsViewWindowScreen> createState() => _ArrowsViewWindowScreenState();
}

class _ArrowsViewWindowScreenState extends State<ArrowsViewWindowScreen>
    with SingleTickerProviderStateMixin {
  static const double _minThicknessScale = 0.6;
  static const double _maxThicknessScale = 3.6;
  static const double _defaultThicknessScale = 1.0;

  ArrowsViewWindowStateManager? _windowStateManager;
  ArrowsViewRuntimeModel? _runtimeModel;
  String? _runtimeError;
  bool _isColoredMode = true;
  double _thicknessScale = _defaultThicknessScale;
  Color _backgroundColor = Colors.transparent;
  bool _isBackgroundColorDialogOpen = false;
  bool _isExporting = false;
  bool _isAnimating = false;
  final TextEditingController _flightSpeedController = TextEditingController(
    text: '1.0',
  );
  final TextEditingController _animationIntervalController =
      TextEditingController(text: '0.25');
  late final Ticker _animationTicker;
  Duration _animationElapsed = Duration.zero;
  final Map<int, Duration> _launchedAt = <int, Duration>{};
  Set<int> _pendingPathIndices = <int>{};
  int _animationRunId = 0;
  static const Duration _flightDuration = Duration(milliseconds: 1300);
  final TextEditingController _exportWidthController = TextEditingController(
    text: '1024',
  );
  final TextEditingController _exportHeightController = TextEditingController(
    text: '1024',
  );
  final ArrowsViewExportService _exportService = ArrowsViewExportService();

  double _clampThicknessScale(double value) {
    return value.clamp(_minThicknessScale, _maxThicknessScale).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _animationTicker = createTicker((elapsed) {
      if (!_isAnimating) {
        return;
      }
      setState(() {
        _animationElapsed = elapsed;
      });
    });
    _buildRuntimeModel();
    _setupWindowState();
  }

  @override
  void dispose() {
    _animationTicker.dispose();
    _flightSpeedController.dispose();
    _animationIntervalController.dispose();
    _windowStateManager?.dispose();
    _exportWidthController.dispose();
    _exportHeightController.dispose();
    super.dispose();
  }

  Future<void> _setupWindowState() async {
    final manager = await ArrowsViewWindowStateManager.setup();
    if (!mounted) {
      manager?.dispose();
      return;
    }
    _windowStateManager = manager;
  }

  void _buildRuntimeModel() {
    try {
      final model = ArrowsViewPathReconstructor().build(widget.snapshot);
      _runtimeModel = model;
      _runtimeError = null;
    } on ArrowsViewRuntimeBuildException catch (error) {
      _runtimeError = error.message;
      _runtimeModel = null;
    } catch (_) {
      _runtimeError = 'Failed to reconstruct paths for this level snapshot.';
      _runtimeModel = null;
    }
  }

  Future<void> _openBackgroundColorEditor() async {
    if (_isBackgroundColorDialogOpen) {
      return;
    }
    _isBackgroundColorDialogOpen = true;
    var tempColor = _backgroundColor;
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Background color'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SizedBox(
                width: 360,
                child: ColorPicker(
                  pickerColor: tempColor,
                  onColorChanged: (nextColor) {
                    setDialogState(() {
                      tempColor = nextColor;
                    });
                  },
                  enableAlpha: true,
                  displayThumbColor: true,
                  portraitOnly: true,
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(tempColor),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    _isBackgroundColorDialogOpen = false;
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _backgroundColor = selected;
    });
  }

  Future<void> _exportPng() async {
    final runtimeModel = _runtimeModel;
    if (runtimeModel == null) {
      _showErrorSnackBar('Nothing to export: path reconstruction failed.');
      return;
    }

    final width = int.tryParse(_exportWidthController.text);
    final height = int.tryParse(_exportHeightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      _showErrorSnackBar('Please enter valid positive export dimensions.');
      return;
    }
    if (width > 8192 || height > 8192) {
      _showErrorSnackBar('Export dimensions are too large (max 8192).');
      return;
    }

    setState(() {
      _isExporting = true;
    });
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final imageSize = Size(width.toDouble(), height.toDouble());
      ArrowsViewBoardPainter.paintForExport(
        canvas: canvas,
        size: imageSize,
        model: runtimeModel,
        settings: ArrowsViewRenderSettings(
          isColored: _isColoredMode,
          thicknessScale: _clampThicknessScale(_thicknessScale),
          backgroundColor: _backgroundColor,
        ),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Failed to encode PNG bytes.');
      }

      final file = await _exportService.savePng(byteData.buffer.asUint8List());
      await _exportService.revealExportFile(file);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved PNG: ${file.path}')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to export PNG: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _startAnimation() async {
    final model = _runtimeModel;
    if (model == null || _isAnimating) {
      return;
    }
    _animationRunId += 1;
    final runId = _animationRunId;
    setState(() {
      _isAnimating = true;
      _animationElapsed = Duration.zero;
      _launchedAt.clear();
      _pendingPathIndices = Set<int>.from(
        List<int>.generate(model.paths.length, (index) => index),
      );
    });
    _animationTicker.start();

    while (mounted && _isAnimating && _pendingPathIndices.isNotEmpty) {
      final releasableIndex = _findNextReleasablePathIndex(model);
      if (releasableIndex == null) {
        break;
      }
      setState(() {
        _pendingPathIndices.remove(releasableIndex);
        _launchedAt[releasableIndex] = _animationElapsed;
      });
      final interval = _readLaunchInterval();
      await Future<void>.delayed(interval);
      if (!mounted || !_isAnimating || runId != _animationRunId) {
        return;
      }
    }

    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted || runId != _animationRunId) {
      return;
    }
    _restoreStaticPreview();
  }

  Duration _readLaunchInterval() {
    final raw = double.tryParse(_animationIntervalController.text);
    if (raw == null || raw <= 0) {
      return const Duration(milliseconds: 250);
    }
    return Duration(milliseconds: (raw * 1000).round());
  }

  double _readFlightSpeed() {
    final raw = double.tryParse(_flightSpeedController.text);
    if (raw == null || raw <= 0) {
      return 1.0;
    }
    return raw;
  }

  void _stopAnimationAndRestore() {
    _animationRunId += 1;
    _restoreStaticPreview();
  }

  int? _findNextReleasablePathIndex(ArrowsViewRuntimeModel model) {
    for (var i = 0; i < model.paths.length; i += 1) {
      if (!_pendingPathIndices.contains(i)) {
        continue;
      }
      if (_isPathReleasable(model, i)) {
        return i;
      }
    }
    return null;
  }

  bool _isPathReleasable(ArrowsViewRuntimeModel model, int candidateIndex) {
    final candidate = model.paths[candidateIndex];
    final dx = candidate.headPose.direction.dx.round();
    final dy = candidate.headPose.direction.dy.round();
    var x = candidate.headPose.position.dx.round() + dx;
    var y = candidate.headPose.position.dy.round() + dy;

    while (x >= 0 && x < model.width && y >= 0 && y < model.height) {
      for (final otherIndex in _pendingPathIndices) {
        if (otherIndex == candidateIndex) {
          continue;
        }
        final points = model.paths[otherIndex].points;
        for (final point in points) {
          if (point.dx.round() == x && point.dy.round() == y) {
            return false;
          }
        }
      }
      x += dx;
      y += dy;
    }
    return true;
  }

  void _restoreStaticPreview() {
    _animationTicker.stop();
    setState(() {
      _isAnimating = false;
      _animationElapsed = Duration.zero;
      _launchedAt.clear();
      _pendingPathIndices = <int>{};
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runtimeModel = _runtimeModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Arrows View')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ArrowsViewControlStrip(
            isColoredMode: _isColoredMode,
            thicknessScale: _thicknessScale,
            minThicknessScale: _minThicknessScale,
            maxThicknessScale: _maxThicknessScale,
            onColoredModeChanged: (value) {
              setState(() {
                _isColoredMode = value;
              });
            },
            onThicknessScaleChanged: (value) {
              setState(() {
                _thicknessScale = _clampThicknessScale(value);
              });
            },
            backgroundColor: _backgroundColor,
            onBackgroundColorTap: _openBackgroundColorEditor,
            onBackgroundColorDoubleTap: _openBackgroundColorEditor,
            flightSpeedController: _flightSpeedController,
            animationIntervalController: _animationIntervalController,
            isAnimating: _isAnimating,
            onAnimatePressed: _startAnimation,
            onStopPressed: _stopAnimationAndRestore,
            exportWidthController: _exportWidthController,
            exportHeightController: _exportHeightController,
            onSavePressed: _isExporting ? null : _exportPng,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: runtimeModel == null
                  ? _ArrowsViewErrorPanel(
                      message: _runtimeError ?? 'Unknown error.',
                    )
                  : ArrowsViewBoardWidget(
                      model: runtimeModel,
                      renderSettings: ArrowsViewRenderSettings(
                        isColored: _isColoredMode,
                        thicknessScale: _clampThicknessScale(_thicknessScale),
                        backgroundColor: _backgroundColor,
                      ),
                      animationFrame: _isAnimating
                          ? ArrowsViewAnimationFrame(
                              pendingPathIndices: _pendingPathIndices,
                              launchedAt: _launchedAt,
                              elapsed: _animationElapsed,
                              flightDuration: _flightDuration,
                              flightSpeed: _readFlightSpeed(),
                            )
                          : null,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowsViewControlStrip extends StatelessWidget {
  const _ArrowsViewControlStrip({
    required this.isColoredMode,
    required this.thicknessScale,
    required this.minThicknessScale,
    required this.maxThicknessScale,
    required this.onColoredModeChanged,
    required this.onThicknessScaleChanged,
    required this.backgroundColor,
    required this.onBackgroundColorTap,
    required this.onBackgroundColorDoubleTap,
    required this.flightSpeedController,
    required this.animationIntervalController,
    required this.isAnimating,
    required this.onAnimatePressed,
    required this.onStopPressed,
    required this.exportWidthController,
    required this.exportHeightController,
    required this.onSavePressed,
  });

  final bool isColoredMode;
  final double thicknessScale;
  final double minThicknessScale;
  final double maxThicknessScale;
  final ValueChanged<bool> onColoredModeChanged;
  final ValueChanged<double> onThicknessScaleChanged;
  final Color backgroundColor;
  final VoidCallback onBackgroundColorTap;
  final VoidCallback onBackgroundColorDoubleTap;
  final TextEditingController flightSpeedController;
  final TextEditingController animationIntervalController;
  final bool isAnimating;
  final VoidCallback onAnimatePressed;
  final VoidCallback onStopPressed;
  final TextEditingController exportWidthController;
  final TextEditingController exportHeightController;
  final VoidCallback? onSavePressed;

  @override
  Widget build(BuildContext context) {
    final sliderValue = thicknessScale
        .clamp(minThicknessScale, maxThicknessScale)
        .toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.palette_outlined, size: 18),
          const SizedBox(width: 6),
          Switch.adaptive(
            value: isColoredMode,
            onChanged: onColoredModeChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 14),
          const Icon(Icons.line_weight, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            child: Slider(
              value: sliderValue,
              min: minThicknessScale,
              max: maxThicknessScale,
              onChanged: onThicknessScaleChanged,
            ),
          ),
          const SizedBox(width: 8),
          _BackgroundColorSwatch(
            color: backgroundColor,
            onTap: onBackgroundColorTap,
            onDoubleTap: onBackgroundColorDoubleTap,
          ),
          const Spacer(),
          _AnimationValueField(
            controller: flightSpeedController,
            icon: Icons.speed,
            width: 92,
          ),
          const SizedBox(width: 6),
          _IntervalField(controller: animationIntervalController),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: isAnimating ? onStopPressed : onAnimatePressed,
            child: Text(isAnimating ? 'Stop' : 'Animate'),
          ),
          const SizedBox(width: 8),
          _ExportDimensionField(
            controller: exportWidthController,
            icon: Icons.straighten,
          ),
          const SizedBox(width: 6),
          _ExportDimensionField(
            controller: exportHeightController,
            icon: Icons.height,
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onSavePressed, child: const Text('Save')),
        ],
      ),
    );
  }
}

class _IntervalField extends StatelessWidget {
  const _IntervalField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.timer_outlined, size: 14),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _AnimationValueField extends StatelessWidget {
  const _AnimationValueField({
    required this.controller,
    required this.icon,
    required this.width,
  });

  final TextEditingController controller;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(icon, size: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _ExportDimensionField extends StatelessWidget {
  const _ExportDimensionField({required this.controller, required this.icon});

  final TextEditingController controller;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(icon, size: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _BackgroundColorSwatch extends StatelessWidget {
  const _BackgroundColorSwatch({
    required this.color,
    required this.onTap,
    required this.onDoubleTap,
  });

  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Tooltip(
        message: 'Click to edit background color',
        child: SizedBox(
          width: 24,
          height: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: _TransparencyGridPainter()),
                  ColoredBox(color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransparencyGridPainter extends CustomPainter {
  const _TransparencyGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xFFE9E9E9);
    final dark = Paint()..color = const Color(0xFFD1D1D1);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isDark = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isDark ? dark : light);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ArrowsViewErrorPanel extends StatelessWidget {
  const _ArrowsViewErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F3),
        border: Border.all(color: const Color(0xFFFFD2D2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Path reconstruction failed',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: const Color(0xFF9A0000)),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5A0000)),
          ),
        ],
      ),
    );
  }
}
