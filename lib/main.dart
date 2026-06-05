import 'package:arrows_level_editor/app/app.dart';
import 'package:arrows_level_editor/app/window_state_manager.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final windowStateManager = await WindowStateManager.setup();
  runApp(ArrowsLevelEditorApp(windowStateManager: windowStateManager));
}
