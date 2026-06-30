import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_painter.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_widget.dart';
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

class _ArrowsViewWindowScreenState extends State<ArrowsViewWindowScreen> {
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

  double _clampThicknessScale(double value) {
    return value.clamp(_minThicknessScale, _maxThicknessScale).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _buildRuntimeModel();
    _setupWindowState();
  }

  @override
  void dispose() {
    _windowStateManager?.dispose();
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
        ],
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
