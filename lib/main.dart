import 'dart:convert';

import 'package:arrows_level_editor/app/app.dart';
import 'package:arrows_level_editor/app/window_state_manager.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_level_snapshot.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_window_screen.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

Future<void> main(List<String> _) async {
  WidgetsFlutterBinding.ensureInitialized();

  final windowLaunch = await _ArrowsViewWindowLaunch.tryParse();
  if (windowLaunch != null) {
    runApp(
      ArrowsLevelEditorApp(
        title: 'Arrows View',
        home: ArrowsViewWindowScreen(snapshot: windowLaunch.snapshot),
      ),
    );
    return;
  }

  final windowStateManager = await WindowStateManager.setup();
  runApp(ArrowsLevelEditorApp(windowStateManager: windowStateManager));
}

class _ArrowsViewWindowLaunch {
  const _ArrowsViewWindowLaunch({required this.snapshot});

  final ArrowsViewLevelSnapshot snapshot;

  static Future<_ArrowsViewWindowLaunch?> tryParse() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      final rawPayload = controller.arguments;
      if (rawPayload.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['windowType'] != 'arrows_view') {
        return null;
      }
      final snapshotJson = decoded['levelSnapshot'];
      if (snapshotJson is! Map<String, dynamic>) {
        return null;
      }
      return _ArrowsViewWindowLaunch(
        snapshot: ArrowsViewLevelSnapshot.fromJson(snapshotJson),
      );
    } catch (_) {
      return null;
    }
  }
}
