import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/state/editor_controller.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_save_validation.dart';
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

  final Set<int> _highlightedErrorCells = <int>{};
  bool _isBlinkOn = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _requestEditorFocus();
      await _loadInitialPack();
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

  Future<void> _loadInitialPack() async {
    if (!mounted || _isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.loadLevelFromDefaultPack();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _handleGenerate() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null) {
      return;
    }
    _controller.generateGrid(width: width, height: height);
  }

  Future<void> _handleOpen() async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.loadLevelFromDefaultPack();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pack opened.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to open pack: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final saved = await _runSaveFlowWithValidation();
      if (!mounted || !saved) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Level saved.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to save level: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<bool> _runSaveFlowWithValidation() async {
    var validation = _controller.validateCurrentLevelBeforeSave();

    while (validation.hasBlockingProblems) {
      final emptyProblems = validation.problems.where(
        (problem) => problem.code == SaveValidationProblemCode.emptyCells,
      );
      if (emptyProblems.isNotEmpty) {
        final cells = emptyProblems.expand((it) => it.cellIndices).toSet();
        await _blinkProblemCells(cells);
        if (!mounted) {
          return false;
        }
        final yes = await _askYesCancel(
          title: 'Empty cells found',
          message: 'Fill all empty cells as inactive and retry save?',
        );
        if (yes != true) {
          return false;
        }
        validation = _controller.applyAutoFixAndRevalidate(
          SaveValidationAutoFixType.fillEmptyCellsAsInactive,
        );
        continue;
      }

      final missingStartProblems = validation.problems.where(
        (problem) => problem.code == SaveValidationProblemCode.missingLineStart,
      );
      if (missingStartProblems.isNotEmpty) {
        final cells = missingStartProblems
            .expand((it) => it.cellIndices)
            .toSet();
        await _blinkProblemCells(cells);
        if (!mounted) {
          return false;
        }
        final hasAutoFix = validation.autoFixes.any(
          (fix) => fix.type == SaveValidationAutoFixType.addTemporaryStarts,
        );
        if (!hasAutoFix) {
          _showErrorSnackBar(
            'Save blocked: some lines have no temporary start candidate.',
          );
          return false;
        }
        final yes = await _askYesCancel(
          title: 'Missing line starts',
          message: 'Place starts automatically for lines without starts?',
        );
        if (yes != true) {
          return false;
        }
        validation = _controller.applyAutoFixAndRevalidate(
          SaveValidationAutoFixType.addTemporaryStarts,
        );
        continue;
      }

      final singleIslands = validation.problems.where(
        (problem) =>
            problem.code == SaveValidationProblemCode.singleCellColorIsland,
      );
      if (singleIslands.isNotEmpty) {
        final cells = singleIslands.expand((it) => it.cellIndices).toSet();
        await _blinkProblemCells(cells);
        if (!mounted) {
          return false;
        }
        _showErrorSnackBar(
          'Save blocked: single-cell color islands must be fixed manually.',
        );
      }
      return false;
    }

    await _controller.saveCurrentLevelToDefaultPack(skipValidation: true);
    return true;
  }

  Future<void> _handleLevelSwitch(String targetLevelId) async {
    if (_isBusy || targetLevelId == _controller.currentLevelId) {
      return;
    }

    if (_controller.isCurrentLevelDirty) {
      final shouldSave = await _askYesCancel(
        title: 'Unsaved changes',
        message: 'Save current level before switching?',
      );
      if (shouldSave != true) {
        return;
      }

      setState(() {
        _isBusy = true;
      });
      try {
        final saved = await _runSaveFlowWithValidation();
        if (!saved) {
          return;
        }
      } finally {
        if (mounted) {
          setState(() {
            _isBusy = false;
          });
        }
      }
    }

    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.loadLevelFromDefaultPack(levelId: targetLevelId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to switch level: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _blinkProblemCells(Set<int> cells) async {
    if (cells.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _highlightedErrorCells
        ..clear()
        ..addAll(cells);
      _isBlinkOn = true;
    });

    for (var i = 0; i < 2; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) {
        return;
      }
      setState(() {
        _isBlinkOn = false;
      });

      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) {
        return;
      }
      setState(() {
        _isBlinkOn = true;
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) {
      return;
    }
    setState(() {
      _isBlinkOn = false;
      _highlightedErrorCells.clear();
    });
  }

  Future<bool?> _askYesCancel({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
                      border: Border(right: BorderSide(color: Colors.black12)),
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
                          const SizedBox(height: 12),
                          _buildFileActions(),
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
                            onColorPick:
                                _controller.selectColorAndActivatePaint,
                            highlightedErrorCells: _isBlinkOn
                                ? Set<int>.from(_highlightedErrorCells)
                                : const <int>{},
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 280,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.black12)),
                    ),
                    child: _buildRightPanel(state),
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

  Widget _buildFileActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isBusy ? null : _handleOpen,
            child: const Text('Open'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _isBusy ? null : _handleSave,
            child: const Text('Save'),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.paletteColors.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final color = state.paletteColors[index];
        final selected = state.selectedColor.toARGB32() == color.toARGB32();
        return InkWell(
          onTap: () => _controller.selectColorAndActivatePaint(color),
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
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
      },
    );
  }

  Widget _buildRightPanel(EditorState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPackSection(),
        const Divider(height: 20),
        _buildLevelsSection(),
        const Divider(height: 20),
        Expanded(child: _buildDebugPanel(state)),
      ],
    );
  }

  Widget _buildPackSection() {
    final packName = _controller.currentPackName ?? 'Not opened yet';
    final dirtyText = _controller.isCurrentLevelDirty ? 'Yes' : 'No';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pack', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Name: $packName'),
        const SizedBox(height: 4),
        Text('Current level: ${_controller.currentLevelId}'),
        const SizedBox(height: 4),
        Text('Unsaved changes: $dirtyText'),
        const SizedBox(height: 4),
        Text('Last validation: ${_validationBrief()}'),
      ],
    );
  }

  Widget _buildLevelsSection() {
    final levels = _controller.availableLevels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Levels', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (levels.isEmpty)
          const Text('No levels in current pack.')
        else
          SizedBox(
            height: 140,
            child: ListView.separated(
              itemCount: levels.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final level = levels[index];
                final selected = level.id == _controller.currentLevelId;
                return ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: selected ? Colors.indigo : Colors.black12,
                    ),
                  ),
                  tileColor: selected
                      ? Colors.indigo.withValues(alpha: 0.08)
                      : null,
                  title: Text(level.id),
                  subtitle: Text(level.path),
                  onTap: _isBusy ? null : () => _handleLevelSwitch(level.id),
                );
              },
            ),
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

    return SingleChildScrollView(
      child: Column(
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
          Text(
            'Internal Preview',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SelectableText(
            _statePreview(state),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
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

  String _validationBrief() {
    final validation = _controller.lastSaveValidationResult;
    if (validation == null) {
      return 'none';
    }
    final blocking = validation.problems
        .where((problem) => problem.isBlocking)
        .length;
    return '$blocking blocking / ${validation.autoFixes.length} auto-fixes';
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
    }
  }
}
