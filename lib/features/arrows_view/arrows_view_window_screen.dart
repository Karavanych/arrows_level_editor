import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_painter.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_board_widget.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_bundled_ffmpeg.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_export_service.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_level_snapshot.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_path_reconstructor.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_runtime_model.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_settings_persistence.dart';
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
  bool _isExportingVideo = false;
  bool _videoStopRequested = false;
  bool _isAnimating = false;
  final TextEditingController _flightSpeedController = TextEditingController(
    text: '2',
  );
  final TextEditingController _animationIntervalController =
      TextEditingController(text: '0.25');
  late final Ticker _animationTicker;
  Duration _animationElapsed = Duration.zero;
  final Map<int, Duration> _launchedAt = <int, Duration>{};
  Set<int> _pendingPathIndices = <int>{};
  int _animationRunId = 0;
  static const Duration _flightDuration = Duration(milliseconds: 2800);
  static const int _videoFps = 30;
  final TextEditingController _exportWidthController = TextEditingController(
    text: '1024',
  );
  final TextEditingController _exportHeightController = TextEditingController(
    text: '1024',
  );
  final ArrowsViewExportService _exportService = ArrowsViewExportService();
  final ArrowsViewSettingsPersistence _settingsPersistence =
      ArrowsViewSettingsPersistence();
  Timer? _settingsSaveDebounce;

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
    _animationIntervalController.addListener(_scheduleSettingsSave);
    _flightSpeedController.addListener(_scheduleSettingsSave);
    _exportWidthController.addListener(_scheduleSettingsSave);
    _exportHeightController.addListener(_scheduleSettingsSave);
    _buildRuntimeModel();
    unawaited(_restorePersistedSettings());
    _setupWindowState();
  }

  @override
  void dispose() {
    _settingsSaveDebounce?.cancel();
    unawaited(_saveSettingsNow());
    _animationIntervalController.removeListener(_scheduleSettingsSave);
    _flightSpeedController.removeListener(_scheduleSettingsSave);
    _exportWidthController.removeListener(_scheduleSettingsSave);
    _exportHeightController.removeListener(_scheduleSettingsSave);
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

  Future<void> _restorePersistedSettings() async {
    final loaded = await _settingsPersistence.load(
      defaultIsColoredMode: true,
      defaultThicknessScale: _defaultThicknessScale,
      minThicknessScale: _minThicknessScale,
      maxThicknessScale: _maxThicknessScale,
      defaultBackgroundColorHexArgb: _toHexArgb(Colors.transparent),
      defaultExportWidthText: '1024',
      defaultExportHeightText: '1024',
      defaultAnimationIntervalText: '0.25',
      defaultFlightSpeedText: '2',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isColoredMode = loaded.isColoredMode;
      _thicknessScale = _clampThicknessScale(loaded.thicknessScale);
      _backgroundColor = _fromHexArgbOrDefault(
        loaded.backgroundColorHexArgb,
        fallback: Colors.transparent,
      );
    });
    _setControllerText(_exportWidthController, loaded.exportWidthText);
    _setControllerText(_exportHeightController, loaded.exportHeightText);
    _setControllerText(
      _animationIntervalController,
      loaded.animationIntervalText,
    );
    _setControllerText(_flightSpeedController, loaded.flightSpeedText);
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _scheduleSettingsSave() {
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveSettingsNow());
    });
  }

  Future<void> _saveSettingsNow() async {
    try {
      await _settingsPersistence.save(
        ArrowsViewPersistedSettings(
          isColoredMode: _isColoredMode,
          thicknessScale: _clampThicknessScale(_thicknessScale),
          backgroundColorHexArgb: _toHexArgb(_backgroundColor),
          exportWidthText: _validatedPositiveIntText(
            _exportWidthController.text,
            fallback: '1024',
          ),
          exportHeightText: _validatedPositiveIntText(
            _exportHeightController.text,
            fallback: '1024',
          ),
          animationIntervalText: _validatedPositiveDoubleText(
            _animationIntervalController.text,
            fallback: '0.25',
          ),
          flightSpeedText: _validatedPositiveDoubleText(
            _flightSpeedController.text,
            fallback: '2',
          ),
        ),
      );
    } catch (_) {
      // Keep ArrowsView usable even when preferences are unavailable.
    }
  }

  String _validatedPositiveIntText(String raw, {required String fallback}) {
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed.toString();
  }

  String _validatedPositiveDoubleText(String raw, {required String fallback}) {
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return raw;
  }

  String _toHexArgb(Color color) {
    return color.toARGB32().toRadixString(16).padLeft(8, '0');
  }

  Color _fromHexArgbOrDefault(String raw, {required Color fallback}) {
    final parsed = int.tryParse(raw, radix: 16);
    if (parsed == null) {
      return fallback;
    }
    return Color(parsed);
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
    _scheduleSettingsSave();
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

  Future<void> _exportVideo() async {
    if (_isExportingVideo) {
      return;
    }
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
      _isExportingVideo = true;
      _videoStopRequested = false;
      _isAnimating = true;
      _animationElapsed = Duration.zero;
      _launchedAt.clear();
      _pendingPathIndices = Set<int>.from(
        List<int>.generate(runtimeModel.paths.length, (index) => index),
      );
    });
    _animationTicker.stop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recording started.')));

    Directory? framesDir;
    try {
      final ffmpeg = resolveBundledFfmpeg();
      await _ensureFfmpegAvailable(ffmpeg.executablePath);
      final tmpRoot = await getTemporaryDirectory();
      framesDir = Directory(
        p.join(
          tmpRoot.path,
          'arrows_view_video_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await framesDir.create(recursive: true);

      final outputFile = await _exportService.createVideoOutputFile();
      final stopwatch = Stopwatch()..start();
      var nextLaunchAt = Duration.zero;
      var frameIndex = 0;
      var hasBlockedPending = false;

      while (mounted && !_videoStopRequested) {
        var elapsed = stopwatch.elapsed;

        while (_pendingPathIndices.isNotEmpty && elapsed >= nextLaunchAt) {
          final releasableIndex = _findNextReleasablePathIndex(runtimeModel);
          if (releasableIndex == null) {
            hasBlockedPending = true;
            break;
          }
          setState(() {
            _pendingPathIndices.remove(releasableIndex);
            _launchedAt[releasableIndex] = elapsed;
          });
          nextLaunchAt += _readLaunchInterval();
          elapsed = stopwatch.elapsed;
        }

        final nextFrameMs = ((frameIndex * 1000.0) / _videoFps).round();
        if (elapsed.inMilliseconds >= nextFrameMs) {
          await _captureVideoFrame(
            runtimeModel: runtimeModel,
            width: width,
            height: height,
            framesDir: framesDir,
            frameIndex: frameIndex,
            elapsed: elapsed,
          );
          frameIndex += 1;
        }

        if (_isVideoAnimationCompleted(
          elapsed: elapsed,
          hasBlockedPending: hasBlockedPending,
        )) {
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 4));
      }

      if (frameIndex < 2) {
        throw const _VideoExportFrameException(
          'Not enough recorded frames to encode MP4.',
        );
      }

      await _encodeFramesToMp4(
        ffmpegPath: ffmpeg.executablePath,
        framesDir: framesDir,
        outputFile: outputFile,
      );
      await _exportService.revealExportFile(outputFile);
      if (!mounted) {
        return;
      }
      final message = _videoStopRequested
          ? 'Recording stopped and saved: ${outputFile.path}'
          : 'Recording finished and saved: ${outputFile.path}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on BundledFfmpegNotFoundException catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(
        'Bundled ffmpeg not found (${error.platformLabel}). Expected: ${error.expectedPath}',
      );
    } on _BundledFfmpegLaunchException catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(
        'Cannot launch ffmpeg (${error.stage}). ${error.message}',
      );
    } on _BundledFfmpegCommandFailedException catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(
        'ffmpeg returned non-zero exit code (${error.stage}): ${error.exitCode}. ${error.details}',
      );
    } on _VideoExportFrameException catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(
        'Frame rendering/export temp data failed: ${error.message}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Encoding failed: $error');
    } finally {
      if (framesDir != null && await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      if (mounted) {
        _restoreStaticPreview();
        setState(() {
          _isExportingVideo = false;
          _videoStopRequested = false;
        });
      } else {
        _animationTicker.stop();
      }
    }
  }

  Future<void> _openVideoExportFolder() async {
    try {
      await _exportService.revealExportDirectory();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to open video export folder: $error');
    }
  }

  Future<void> _captureVideoFrame({
    required ArrowsViewRuntimeModel runtimeModel,
    required int width,
    required int height,
    required Directory framesDir,
    required int frameIndex,
    required Duration elapsed,
  }) async {
    setState(() {
      _animationElapsed = elapsed;
    });
    final frame = ArrowsViewAnimationFrame(
      pendingPathIndices: Set<int>.from(_pendingPathIndices),
      launchedAt: Map<int, Duration>.from(_launchedAt),
      elapsed: elapsed,
      flightDuration: _flightDuration,
      flightSpeed: _readFlightSpeed(),
    );
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
        backgroundColor: _opaqueVideoBackground(_backgroundColor),
      ),
      animationFrame: frame,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw const _VideoExportFrameException(
        'Failed to encode frame PNG bytes.',
      );
    }
    final framePath = p.join(
      framesDir.path,
      'frame_${frameIndex.toString().padLeft(6, '0')}.png',
    );
    await File(
      framePath,
    ).writeAsBytes(byteData.buffer.asUint8List(), flush: true);
  }

  Future<void> _ensureFfmpegAvailable(String ffmpegPath) async {
    ProcessResult result;
    try {
      result = await Process.run(ffmpegPath, ['-version']);
    } on ProcessException catch (error) {
      throw _BundledFfmpegLaunchException.from(
        processException: error,
        ffmpegPath: ffmpegPath,
        stage: 'validation',
      );
    }
    if (result.exitCode != 0) {
      throw _BundledFfmpegCommandFailedException(
        stage: 'validation',
        exitCode: result.exitCode,
        details: _summarizeProcessFailure(result),
      );
    }
  }

  Future<void> _encodeFramesToMp4({
    required String ffmpegPath,
    required Directory framesDir,
    required File outputFile,
  }) async {
    final inputPattern = p.join(framesDir.path, 'frame_%06d.png');
    ProcessResult result;
    try {
      result = await Process.run(ffmpegPath, [
        '-y',
        '-framerate',
        '$_videoFps',
        '-i',
        inputPattern,
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        outputFile.path,
      ]);
    } on ProcessException catch (error) {
      throw _BundledFfmpegLaunchException.from(
        processException: error,
        ffmpegPath: ffmpegPath,
        stage: 'encoding',
      );
    }
    if (result.exitCode != 0) {
      throw _BundledFfmpegCommandFailedException(
        stage: 'encoding',
        exitCode: result.exitCode,
        details: _summarizeProcessFailure(result),
      );
    }
  }

  String _summarizeProcessFailure(ProcessResult result) {
    final stderr = result.stderr?.toString().trim() ?? '';
    final stdout = result.stdout?.toString().trim() ?? '';
    if (stderr.isNotEmpty) {
      return stderr;
    }
    if (stdout.isNotEmpty) {
      return stdout;
    }
    return 'No stdout/stderr output from ffmpeg.';
  }

  bool _isVideoAnimationCompleted({
    required Duration elapsed,
    required bool hasBlockedPending,
  }) {
    if (_pendingPathIndices.isNotEmpty && !hasBlockedPending) {
      return false;
    }
    if (_launchedAt.isEmpty) {
      return hasBlockedPending || _pendingPathIndices.isEmpty;
    }
    final speed = _readFlightSpeed();
    final effectiveSpeed = speed <= 0 ? 1.0 : speed;
    final perArrowDuration = Duration(
      milliseconds: (_flightDuration.inMilliseconds / effectiveSpeed).ceil(),
    );
    for (final launchAt in _launchedAt.values) {
      if (elapsed < launchAt + perArrowDuration) {
        return false;
      }
    }
    return true;
  }

  Color _opaqueVideoBackground(Color base) {
    const fallback = Color(0xFFF3F3F3);
    final alpha255 = (base.a * 255.0).round().clamp(0, 255);
    if (alpha255 == 255) {
      return base;
    }
    return Color.alphaBlend(base, fallback);
  }

  Future<void> _startAnimation() async {
    final model = _runtimeModel;
    if (model == null || _isAnimating || _isExportingVideo) {
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
      return 2.0;
    }
    return raw;
  }

  void _stopAnimationAndRestore() {
    if (_isExportingVideo) {
      _videoStopRequested = true;
      return;
    }
    _animationRunId += 1;
    _restoreStaticPreview();
  }

  int? _findNextReleasablePathIndex(ArrowsViewRuntimeModel model) {
    for (var i = 0; i < model.paths.length; i += 1) {
      if (!_pendingPathIndices.contains(i)) {
        continue;
      }
      if (_isPathReleasableForSet(model, i, _pendingPathIndices)) {
        return i;
      }
    }
    return null;
  }

  bool _isPathReleasableForSet(
    ArrowsViewRuntimeModel model,
    int candidateIndex,
    Set<int> pendingSet,
  ) {
    final candidate = model.paths[candidateIndex];
    final dx = candidate.headPose.direction.dx.round();
    final dy = candidate.headPose.direction.dy.round();
    var x = candidate.headPose.position.dx.round() + dx;
    var y = candidate.headPose.position.dy.round() + dy;

    while (x >= 0 && x < model.width && y >= 0 && y < model.height) {
      for (final otherIndex in pendingSet) {
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
              _scheduleSettingsSave();
            },
            onThicknessScaleChanged: (value) {
              setState(() {
                _thicknessScale = _clampThicknessScale(value);
              });
              _scheduleSettingsSave();
            },
            backgroundColor: _backgroundColor,
            onBackgroundColorTap: _openBackgroundColorEditor,
            onBackgroundColorDoubleTap: _openBackgroundColorEditor,
            flightSpeedController: _flightSpeedController,
            animationIntervalController: _animationIntervalController,
            isAnimating: _isAnimating,
            isRecordingVideo: _isExportingVideo,
            onAnimatePressed: _startAnimation,
            onStopPressed: _stopAnimationAndRestore,
            onSaveVideoPressed: (_isExportingVideo || _isAnimating)
                ? null
                : _exportVideo,
            onOpenVideosPressed: _openVideoExportFolder,
            onStopVideoPressed: _isExportingVideo
                ? () {
                    _videoStopRequested = true;
                  }
                : null,
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
    required this.isRecordingVideo,
    required this.onAnimatePressed,
    required this.onStopPressed,
    required this.onSaveVideoPressed,
    required this.onOpenVideosPressed,
    required this.onStopVideoPressed,
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
  final bool isRecordingVideo;
  final VoidCallback onAnimatePressed;
  final VoidCallback onStopPressed;
  final VoidCallback? onSaveVideoPressed;
  final VoidCallback? onOpenVideosPressed;
  final VoidCallback? onStopVideoPressed;
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            const SizedBox(width: 16),
            FilledButton(
              onPressed: isRecordingVideo
                  ? onStopVideoPressed
                  : onSaveVideoPressed,
              child: Text(isRecordingVideo ? 'Stop' : 'Save Video'),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onOpenVideosPressed,
              child: const Text('Open Videos'),
            ),
            const SizedBox(width: 8),
            _AnimationValueField(
              controller: flightSpeedController,
              icon: Icons.speed,
              width: 92,
            ),
            const SizedBox(width: 6),
            _IntervalField(controller: animationIntervalController),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: isRecordingVideo
                  ? null
                  : (isAnimating ? onStopPressed : onAnimatePressed),
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

class _BundledFfmpegLaunchException implements Exception {
  const _BundledFfmpegLaunchException({
    required this.stage,
    required this.message,
  });

  factory _BundledFfmpegLaunchException.from({
    required ProcessException processException,
    required String ffmpegPath,
    required String stage,
  }) {
    final details = processException.message;
    return _BundledFfmpegLaunchException(
      stage: stage,
      message: '$details (path: $ffmpegPath)',
    );
  }

  final String stage;
  final String message;
}

class _BundledFfmpegCommandFailedException implements Exception {
  const _BundledFfmpegCommandFailedException({
    required this.stage,
    required this.exitCode,
    required this.details,
  });

  final String stage;
  final int exitCode;
  final String details;
}

class _VideoExportFrameException implements Exception {
  const _VideoExportFrameException(this.message);

  final String message;
}
