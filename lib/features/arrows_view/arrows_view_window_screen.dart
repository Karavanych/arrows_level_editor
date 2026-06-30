import 'package:flutter/material.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_level_snapshot.dart';
import 'package:arrows_level_editor/features/arrows_view/arrows_view_window_state_manager.dart';

class ArrowsViewWindowScreen extends StatefulWidget {
  const ArrowsViewWindowScreen({super.key, required this.snapshot});

  final ArrowsViewLevelSnapshot snapshot;

  @override
  State<ArrowsViewWindowScreen> createState() => _ArrowsViewWindowScreenState();
}

class _ArrowsViewWindowScreenState extends State<ArrowsViewWindowScreen> {
  ArrowsViewWindowStateManager? _windowStateManager;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arrows View')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Level payload received',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text('Level id: ${widget.snapshot.levelId}'),
            Text(
              'Size: ${widget.snapshot.gridWidth} x ${widget.snapshot.gridHeight}',
            ),
            Text('Cells: ${widget.snapshot.cells.length}'),
            Text('Start points: ${widget.snapshot.startPoints.length}'),
            Text('Palette colors: ${widget.snapshot.paletteColors.length}'),
            Text('Selected tool: ${widget.snapshot.selectedTool}'),
            const SizedBox(height: 16),
            const Text(
              'Arrow rendering is not implemented yet.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
