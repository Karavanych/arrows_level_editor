import 'package:arrows_level_editor/features/editor/editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:arrows_level_editor/app/window_state_manager.dart';

class ArrowsLevelEditorApp extends StatefulWidget {
  const ArrowsLevelEditorApp({
    super.key,
    this.windowStateManager,
    this.home = const EditorScreen(),
    this.title = 'Arrows Level Editor',
  });

  final WindowStateManager? windowStateManager;
  final Widget home;
  final String title;

  @override
  State<ArrowsLevelEditorApp> createState() => _ArrowsLevelEditorAppState();
}

class _ArrowsLevelEditorAppState extends State<ArrowsLevelEditorApp> {
  @override
  void dispose() {
    widget.windowStateManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: widget.home,
    );
  }
}
