import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class ArrowsViewWindowStateManager with WindowListener {
  ArrowsViewWindowStateManager._(this._prefs);

  static const _widthKey = 'arrows_view.window.width';
  static const _heightKey = 'arrows_view.window.height';
  static const _xKey = 'arrows_view.window.x';
  static const _yKey = 'arrows_view.window.y';
  static const _maximizedKey = 'arrows_view.window.maximized';
  static const _fallbackWidth = 560.0;
  static const _fallbackHeight = 720.0;

  final SharedPreferences _prefs;
  Timer? _saveDebounce;

  static Future<ArrowsViewWindowStateManager?> setup() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return null;
    }
    try {
      await windowManager.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final manager = ArrowsViewWindowStateManager._(prefs);
      await manager._restoreOrApplyDefaultBounds();
      windowManager.addListener(manager);
      return manager;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _saveDebounce?.cancel();
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.removeListener(this);
    }
  }

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();

  @override
  void onWindowClose() {
    _saveDebounce?.cancel();
    unawaited(_saveNow());
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveNow());
    });
  }

  Future<void> _restoreOrApplyDefaultBounds() async {
    final savedWidth = _prefs.getDouble(_widthKey);
    final savedHeight = _prefs.getDouble(_heightKey);
    final savedX = _prefs.getDouble(_xKey);
    final savedY = _prefs.getDouble(_yKey);
    final savedMaximized = _prefs.getBool(_maximizedKey) ?? false;
    final visibleRect = await _getPrimaryVisibleRect();

    final hasSavedRect =
        savedWidth != null &&
        savedHeight != null &&
        savedX != null &&
        savedY != null &&
        savedWidth > 0 &&
        savedHeight > 0;

    late final Size targetSize;
    late final Offset targetPosition;
    if (hasSavedRect &&
        _isRectVisible(
          position: Offset(savedX, savedY),
          size: Size(savedWidth, savedHeight),
          visibleRect: visibleRect,
        )) {
      targetSize = Size(savedWidth, savedHeight);
      targetPosition = Offset(savedX, savedY);
    } else {
      targetSize = Size(_fallbackWidth, _fallbackHeight);
      targetPosition = _centeredPosition(targetSize, visibleRect);
    }

    await windowManager.setMinimumSize(const Size(420, 420));
    await windowManager.setSize(targetSize);
    await windowManager.setPosition(targetPosition);
    if (savedMaximized) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _saveNow() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      await _prefs.setBool(_maximizedKey, isMaximized);
      if (isMaximized) {
        return;
      }

      final bounds = await windowManager.getBounds();
      await _prefs.setDouble(_widthKey, bounds.width);
      await _prefs.setDouble(_heightKey, bounds.height);
      await _prefs.setDouble(_xKey, bounds.left);
      await _prefs.setDouble(_yKey, bounds.top);
    } catch (_) {
      // Keep window usable if bounds persistence is unavailable on a platform.
    }
  }

  Future<Rect> _getPrimaryVisibleRect() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final visibleSize = display.visibleSize ?? display.size;
    final visiblePosition = display.visiblePosition ?? Offset.zero;
    return Rect.fromLTWH(
      visiblePosition.dx,
      visiblePosition.dy,
      visibleSize.width,
      visibleSize.height,
    );
  }

  bool _isRectVisible({
    required Offset position,
    required Size size,
    required Rect visibleRect,
  }) {
    final rect = Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );
    return rect.overlaps(visibleRect);
  }

  Offset _centeredPosition(Size size, Rect visibleRect) {
    return Offset(
      visibleRect.left + (visibleRect.width - size.width) / 2,
      visibleRect.top + (visibleRect.height - size.height) / 2,
    );
  }
}
