import 'package:flutter/material.dart';

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
  static const double _maxThicknessScale = 1.8;
  static const double _defaultThicknessScale = 1.0;

  ArrowsViewWindowStateManager? _windowStateManager;
  ArrowsViewRuntimeModel? _runtimeModel;
  String? _runtimeError;
  bool _isColoredMode = true;
  double _thicknessScale = _defaultThicknessScale;

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
  });

  final bool isColoredMode;
  final double thicknessScale;
  final double minThicknessScale;
  final double maxThicknessScale;
  final ValueChanged<bool> onColoredModeChanged;
  final ValueChanged<double> onThicknessScaleChanged;

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
          const Spacer(),
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
        ],
      ),
    );
  }
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
