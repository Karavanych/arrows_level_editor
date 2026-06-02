import 'package:arrows_level_editor/features/editor/editor_screen.dart';
import 'package:flutter/material.dart';

class ArrowsLevelEditorApp extends StatelessWidget {
  const ArrowsLevelEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arrows Level Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const EditorScreen(),
    );
  }
}
