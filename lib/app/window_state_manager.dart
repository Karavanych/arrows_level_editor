import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowStateManager with WindowListener {
  WindowStateManager._(this._prefs);

  static const _widthKey = 'window.width';
  static const _heightKey = 'window.height';
  static const _xKey = 'window.x';
  static const _yKey = 'window.y';
  static const _maximizedKey = 'window.maximized';

  final SharedPreferences _prefs;
  Timer? _saveDebounce;

  static Future<WindowStateManager?> setup() async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return null;
    }

    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final manager = WindowStateManager._(prefs);
    await manager._restoreOrApplyDefaultBounds();
    windowManager.addListener(manager);
    return manager;
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

    final hasSavedRect =
        savedWidth != null &&
        savedHeight != null &&
        savedX != null &&
        savedY != null &&
        savedWidth > 0 &&
        savedHeight > 0;

    final visibleRect = await _getPrimaryVisibleRect();

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
      targetSize = _defaultLargeSize(visibleRect);
      targetPosition = _centeredPosition(targetSize, visibleRect);
    }

    await windowManager.setMinimumSize(const Size(900, 600));
    await windowManager.setSize(targetSize);
    await windowManager.setPosition(targetPosition);
    await windowManager.show();
    await windowManager.focus();
    if (savedMaximized) {
      await windowManager.maximize();
    }
  }

  Future<void> _saveNow() async {
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

  Size _defaultLargeSize(Rect visibleRect) {
    final width = (visibleRect.width * 0.85).clamp(1000.0, 1800.0);
    final height = (visibleRect.height * 0.85).clamp(700.0, 1200.0);
    return Size(width, height);
  }

  Offset _centeredPosition(Size size, Rect visibleRect) {
    return Offset(
      visibleRect.left + (visibleRect.width - size.width) / 2,
      visibleRect.top + (visibleRect.height - size.height) / 2,
    );
  }
}
