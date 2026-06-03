import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/state/editor_controller.dart';
import 'package:arrows_level_editor/features/editor/widgets/editor_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorController _controller = EditorController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _widthController = TextEditingController(
    text: '10',
  );
  final TextEditingController _heightController = TextEditingController(
    text: '10',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestEditorFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _handleGenerate() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null) {
      return;
    }
    _controller.generateGrid(width: width, height: height);
  }

  void _requestEditorFocus() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _onGridInteractionStart() {
    _requestEditorFocus();
  }

  KeyEventResult _handleEditorKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isPrimaryShortcutModifierPressed = isMetaPressed || isControlPressed;

    if (!isPrimaryShortcutModifierPressed) {
      return KeyEventResult.ignored;
    }

    if (event is KeyRepeatEvent &&
        (key == LogicalKeyboardKey.keyZ || key == LogicalKeyboardKey.keyY)) {
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.keyZ) {
      if (isShiftPressed) {
        _controller.redo();
      } else {
        _controller.undo();
      }
      return KeyEventResult.handled;
    }

    if (!isMetaPressed && isControlPressed && key == LogicalKeyboardKey.keyY) {
      _controller.redo();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          onKeyEvent: (_, event) => _handleEditorKeyEvent(event),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final state = _controller.state;
              return Row(
                children: [
                  Container(
                    width: 280,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.black12),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Arrows Level Editor',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          _buildDimensionInputs(),
                          const SizedBox(height: 20),
                          Text(
                            'Tool',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _buildToolSelector(state),
                          const SizedBox(height: 20),
                          Text(
                            'Color Palette',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _buildColorPalette(state),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF5F5F5),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: EditorGridView(
                            state: state,
                            onStrokeStart: _controller.beginStroke,
                            onCellDrag: _controller.touchCell,
                            onStrokeEnd: _controller.endStroke,
                            onEraseStrokeStart: _controller.beginEraseStroke,
                            onEraseCellDrag: _controller.eraseCell,
                            onEraseStrokeEnd: _controller.endEraseStroke,
                            onEditorInteractionStart: _onGridInteractionStart,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 250,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.black12)),
                    ),
                    child: _buildDebugPanel(state),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDimensionInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _widthController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Grid Width',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _heightController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Grid Height',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _handleGenerate,
            child: const Text('Generate'),
          ),
        ),
      ],
    );
  }

  Widget _buildToolSelector(EditorState state) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: EditorTool.values.map((tool) {
        return ChoiceChip(
          label: Text(_toolLabel(tool)),
          selected: state.selectedTool == tool,
          onSelected: (_) => _controller.selectTool(tool),
        );
      }).toList(),
    );
  }

  Widget _buildColorPalette(EditorState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: state.paletteColors.map((color) {
            final selected = state.selectedColor.toARGB32() == color.toARGB32();
            return InkWell(
              onTap: () => _controller.selectColor(color),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? Colors.black : Colors.black26,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.color_lens_outlined),
          label: const Text('Add/Edit Color'),
        ),
        const SizedBox(height: 4),
        Text(
          'TODO: Wire a lightweight color picker after palette needs settle.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildDebugPanel(EditorState state) {
    final inactiveCount = state.cells.where((cell) => cell.isInactive).length;
    final markerCount = state.cells.where((cell) => cell.hasStartMarker).length;
    final paintedCount = state.cells
        .where((cell) => cell.paintColor != null)
        .length;
    final selectedCell = _selectedCell(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('State Preview', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text('Grid: ${state.gridSize.width} x ${state.gridSize.height}'),
        const Divider(height: 20),
        Text('Selected tool: ${_toolLabel(state.selectedTool)}'),
        const SizedBox(height: 8),
        Text('Selected color: ${_colorLabel(state.selectedColor)}'),
        const SizedBox(height: 8),
        Text('Painted cells: $paintedCount'),
        const SizedBox(height: 4),
        Text('Inactive cells: $inactiveCount'),
        const SizedBox(height: 4),
        Text('Start markers: $markerCount'),
        const Divider(height: 28),
        Text('Selected Cell', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (selectedCell == null)
          const Text('None')
        else ...[
          Text('Index: ${state.selectedCellIndex}'),
          const SizedBox(height: 4),
          Text('Color: ${_colorLabel(selectedCell.paintColor)}'),
          const SizedBox(height: 4),
          Text('Inactive: ${selectedCell.isInactive}'),
          const SizedBox(height: 4),
          Text('Start marker: ${selectedCell.hasStartMarker}'),
        ],
        const Divider(height: 28),
        Text('Internal Preview', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(
              _statePreview(state),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }

  EditorCell? _selectedCell(EditorState state) {
    final index = state.selectedCellIndex;
    if (index == null || index < 0 || index >= state.cells.length) {
      return null;
    }
    return state.cells[index];
  }

  String _statePreview(EditorState state) {
    final editedCells = <String>[];
    for (var index = 0; index < state.cells.length; index += 1) {
      final cell = state.cells[index];
      if (cell.paintColor == null && !cell.isInactive && !cell.hasStartMarker) {
        continue;
      }
      editedCells.add(
        '{index: $index, color: ${_colorLabel(cell.paintColor)}, '
        'inactive: ${cell.isInactive}, start: ${cell.hasStartMarker}}',
      );
      if (editedCells.length == 12) {
        break;
      }
    }

    return '''
{
  grid: ${state.gridSize.width}x${state.gridSize.height},
  tool: ${_toolLabel(state.selectedTool)},
  selectedColor: ${_colorLabel(state.selectedColor)},
  selectedCell: ${state.selectedCellIndex},
  editedCellsPreview: [
    ${editedCells.isEmpty ? '// none' : editedCells.join(',\n    ')}
  ]
}''';
  }

  String _colorLabel(Color? color) {
    if (color == null) {
      return 'none';
    }
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
  }

  String _toolLabel(EditorTool tool) {
    switch (tool) {
      case EditorTool.paint:
        return 'Paint';
      case EditorTool.inactive:
        return 'Inactive';
      case EditorTool.startMarker:
        return 'Start';
      case EditorTool.erase:
        return 'Erase';
      case EditorTool.select:
        return 'Select';
    }
  }
}
