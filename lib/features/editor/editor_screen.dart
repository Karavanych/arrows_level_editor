import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/state/editor_controller.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_check_preview_simulation.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_save_validation.dart';
import 'package:arrows_level_editor/features/editor/widgets/editor_grid_view.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
  String? _lastSyncedLevelId;
  int? _lastSyncedLevelWidth;
  int? _lastSyncedLevelHeight;
  final EditorCheckPreviewSimulationService _checkPreviewSimulationService =
      EditorCheckPreviewSimulationService();

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

  Future<void> _handleCreateLevel() async {
    if (_isBusy) {
      return;
    }
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null) {
      return;
    }

    if (_controller.isCurrentLevelCompletelyEmpty) {
      setState(() {
        _isBusy = true;
      });
      try {
        await _controller.recreateCurrentLevel(width: width, height: height);
        _controller.markCurrentLevelChecked(false);
      } catch (error) {
        if (!mounted) {
          return;
        }
        _showErrorSnackBar('Failed to recreate level: $error');
      } finally {
        if (mounted) {
          setState(() {
            _isBusy = false;
          });
        }
      }
      return;
    }

    if (_controller.isCurrentLevelDirty) {
      final action = await _askCreateLevelDirtyAction();
      if (action == _DirtyCreateLevelAction.cancel || action == null) {
        return;
      }
      if (action == _DirtyCreateLevelAction.save) {
        setState(() {
          _isBusy = true;
        });
        try {
          await _controller.saveCurrentLevelToDefaultPack();
        } finally {
          if (mounted) {
            setState(() {
              _isBusy = false;
            });
          }
        }
      }
      if (action == _DirtyCreateLevelAction.discard) {
        setState(() {
          _isBusy = true;
        });
        try {
          await _controller.discardUnsavedChangesForCurrentLevel();
        } finally {
          if (mounted) {
            setState(() {
              _isBusy = false;
            });
          }
        }
      }
    }

    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.createLevel(width: width, height: height);
      _controller.markCurrentLevelChecked(false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('New level created.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to create level: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
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
      await _controller.saveCurrentLevelToDefaultPack();
      if (!mounted) {
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

  Future<void> _handleCheckLevel() async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final passed = await _runCheckLevelValidationFlow();
      if (!mounted) {
        return;
      }
      if (!passed) {
        _controller.markCurrentLevelChecked(false);
        return;
      }

      final previewPassed = await _runFinalCheckPreviewSimulation();
      if (!mounted) {
        return;
      }
      if (!previewPassed) {
        _controller.markCurrentLevelChecked(false);
        return;
      }

      _controller.markCurrentLevelChecked(true);
      await _controller.persistCurrentPackState();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Level check passed.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _controller.markCurrentLevelChecked(false);
      _showErrorSnackBar('Failed to check level: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<bool> _runCheckLevelValidationFlow() async {
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
        final shouldFill = await _askYesCancel(
          title: 'Empty cells found',
          message: 'Fill all empty cells as inactive?',
        );
        if (shouldFill != true) {
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
            'Check failed: some lines have no temporary start candidate.',
          );
          return false;
        }
        final shouldAddStarts = await _askYesCancel(
          title: 'Missing line starts',
          message: 'Place starts automatically for lines without starts?',
        );
        if (shouldAddStarts != true) {
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
          'Check failed: single-cell color islands must be fixed manually.',
        );
        return false;
      }

      return false;
    }

    return true;
  }

  Future<bool> _runFinalCheckPreviewSimulation() async {
    final baseState = _controller.state.copyWith(
      cells: List<EditorCell>.from(_controller.state.cells),
      paletteColors: List<Color>.from(_controller.state.paletteColors),
    );
    final previewStateNotifier = ValueNotifier<EditorState>(baseState);
    final statusNotifier = ValueNotifier<String>('running');

    Future<CheckPreviewSimulationOutcome> runOneAttempt() async {
      return _checkPreviewSimulationService.run(
        baseState: baseState,
        onStep: (state, status) {
          previewStateNotifier.value = state;
          statusNotifier.value = status;
        },
        onBlocked: () async {
          final decision = await _askYesCancel(
            title: 'Lines block each other',
            message: 'Lines block each other. Try opposite start points?',
          );
          return decision == true;
        },
      );
    }

    final result = await showDialog<CheckPreviewSimulationOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        Future<CheckPreviewSimulationOutcome>? pendingRun;

        Future<void> ensureRun() async {
          pendingRun ??= runOneAttempt();
          final outcome = await pendingRun!;
          if (!dialogContext.mounted) {
            return;
          }
          statusNotifier.value = outcome.passed ? 'passed' : 'failed';
        }

        ensureRun();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> retry() async {
              statusNotifier.value = 'running';
              previewStateNotifier.value = baseState;
              pendingRun = runOneAttempt();
              final outcome = await pendingRun!;
              if (!dialogContext.mounted) {
                return;
              }
              statusNotifier.value = outcome.passed ? 'passed' : 'failed';
              setDialogState(() {});
            }

            return Dialog(
              child: SizedBox(
                width: 760,
                height: 720,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check Level Preview',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<String>(
                        valueListenable: statusNotifier,
                        builder: (context, status, child) {
                          return Text('Status: $status');
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          color: const Color(0xFFF5F5F5),
                          child: ValueListenableBuilder<EditorState>(
                            valueListenable: previewStateNotifier,
                            builder: (context, previewState, child) {
                              return EditorGridView(
                                state: previewState,
                                onStrokeStart: (_) {},
                                onCellDrag: (_) {},
                                onStrokeEnd: () {},
                                onEraseStrokeStart: (_) {},
                                onEraseCellDrag: (_) {},
                                onEraseStrokeEnd: () {},
                                onEditorInteractionStart: () {},
                                onColorPick: (_) {},
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: retry,
                            child: const Text('Retry'),
                          ),
                          const Spacer(),
                          ValueListenableBuilder<String>(
                            valueListenable: statusNotifier,
                            builder: (context, status, child) {
                              if (status != 'passed') {
                                return FilledButton(
                                  onPressed: null,
                                  child: const Text('Apply & Close'),
                                );
                              }
                              return FilledButton(
                                onPressed: () async {
                                  final outcome = await pendingRun;
                                  if (!dialogContext.mounted || outcome == null) {
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop(outcome);
                                },
                                child: const Text('Apply & Close'),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    previewStateNotifier.dispose();
    statusNotifier.dispose();

    if (result == null || !result.passed) {
      return false;
    }

    _controller.replaceCurrentLevelStartMarkersFromState(result.startPlanState);
    return true;
  }

  Future<void> _handleReveal() async {
    if (_isBusy) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.revealDefaultPackFolder();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to reveal pack folder: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _handleLevelSwitch(String targetLevelId) async {
    if (_isBusy || targetLevelId == _controller.currentLevelId) {
      return;
    }

    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.switchToLevel(targetLevelId);
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

  Future<void> _handleDeleteLevel(String targetLevelId) async {
    if (_isBusy) {
      return;
    }
    final shouldDelete = await _askDeleteLevelConfirmation();
    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.deleteLevelById(targetLevelId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to delete level: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _handleEraseAll() async {
    if (_isBusy) {
      return;
    }

    final shouldClear = await _askYesCancel(
      title: 'Clear level?',
      message:
          'Are you sure you want to clear the entire level? You will lose everything you have drawn.',
    );
    if (shouldClear != true) {
      return;
    }

    _controller.clearCurrentLevelContents();
    _controller.markCurrentLevelChecked(false);
  }

  Future<void> _handleLevelsReorder(int oldIndex, int newIndex) async {
    if (_isBusy) {
      return;
    }
    if (oldIndex == newIndex) {
      return;
    }

    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.reorderLevels(oldIndex: oldIndex, newIndex: newIndex);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to reorder levels: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _handleEditPaletteColor({
    required int index,
    required Color initialColor,
  }) async {
    if (_isBusy) {
      return;
    }

    var candidateColor = initialColor;
    final reservedInactiveColor = _controller.inactiveReservedColor;
    final reservedArgb = reservedInactiveColor.toARGB32();
    String? validationMessage;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedArgb = candidateColor.toARGB32();
            final isReserved = selectedArgb == reservedArgb;
            validationMessage = isReserved
                ? 'This color is reserved for inactive cells and cannot be used in palette slots.'
                : null;
            return AlertDialog(
              title: const Text('Edit palette color'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ColorPicker(
                      pickerColor: candidateColor,
                      onColorChanged: (next) {
                        setDialogState(() {
                          candidateColor = next;
                        });
                      },
                      enableAlpha: false,
                      displayThumbColor: true,
                      portraitOnly: true,
                    ),
                    if (validationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isReserved
                      ? null
                      : () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isBusy = true;
    });
    try {
      await _controller.updatePaletteColorAt(index: index, color: candidateColor);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar('Failed to update palette color: $error');
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

  Future<bool?> _askDeleteLevelConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete level'),
          content: const Text('Are you sure you want to delete this level?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
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

  Future<_DirtyCreateLevelAction?> _askCreateLevelDirtyAction() {
    return showDialog<_DirtyCreateLevelAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'Current level has unsaved changes. What do you want to do before creating a new level?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_DirtyCreateLevelAction.cancel),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_DirtyCreateLevelAction.discard),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_DirtyCreateLevelAction.save),
              child: const Text('Save'),
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

  void _syncDimensionInputsWithCurrentLevel(EditorState state) {
    final currentLevelId = _controller.currentLevelId;
    final currentWidth = state.gridSize.width;
    final currentHeight = state.gridSize.height;
    final needsSync =
        _lastSyncedLevelId != currentLevelId ||
        _lastSyncedLevelWidth != currentWidth ||
        _lastSyncedLevelHeight != currentHeight;
    if (!needsSync) {
      return;
    }

    final nextWidthText = currentWidth.toString();
    if (_widthController.text != nextWidthText) {
      _widthController.value = TextEditingValue(
        text: nextWidthText,
        selection: TextSelection.collapsed(offset: nextWidthText.length),
      );
    }

    final nextHeightText = currentHeight.toString();
    if (_heightController.text != nextHeightText) {
      _heightController.value = TextEditingValue(
        text: nextHeightText,
        selection: TextSelection.collapsed(offset: nextHeightText.length),
      );
    }

    _lastSyncedLevelId = currentLevelId;
    _lastSyncedLevelWidth = currentWidth;
    _lastSyncedLevelHeight = currentHeight;
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
              _syncDimensionInputsWithCurrentLevel(state);
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
                          const SizedBox(height: 12),
                          Center(
                            child: FilledButton(
                              onPressed: _isBusy ? null : _handleCheckLevel,
                              child: const Text('Check Level'),
                            ),
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
                          const SizedBox(height: 12),
                          _buildBrushModeSelector(),
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
                            isLineModeEnabled:
                                _controller.isLineBrushModeEnabledForCurrentTool,
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
            onPressed: _isBusy ? null : _handleCreateLevel,
            child: const Text('Create Level'),
          ),
        ),
      ],
    );
  }

  Widget _buildToolSelector(EditorState state) {
    final toolChips = EditorTool.values.map((tool) {
      return ChoiceChip(
        label: Text(_toolLabel(tool)),
        selected: state.selectedTool == tool,
        onSelected: (_) => _controller.selectTool(tool),
      );
    }).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...toolChips,
        OutlinedButton(
          onPressed: _isBusy ? null : _handleEraseAll,
          child: const Text('Erase All'),
        ),
      ],
    );
  }

  Widget _buildBrushModeSelector() {
    final selectedMode = _controller.brushApplicationMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Apply Mode',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        SegmentedButton<BrushApplicationMode>(
          segments: const [
            ButtonSegment<BrushApplicationMode>(
              value: BrushApplicationMode.point,
              icon: Icon(Icons.grid_on, size: 16),
              label: Text('Point'),
            ),
            ButtonSegment<BrushApplicationMode>(
              value: BrushApplicationMode.line,
              icon: Icon(Icons.horizontal_rule, size: 18),
              label: Text('Line'),
            ),
          ],
          selected: {selectedMode},
          onSelectionChanged: (selection) {
            final next = selection.firstOrNull;
            if (next == null) {
              return;
            }
            _controller.setBrushApplicationMode(next);
          },
        ),
      ],
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
          onDoubleTap: () =>
              _handleEditPaletteColor(index: index, initialColor: color),
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
        Text('Current Level', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          _controller.currentLevelId,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildRightPanelActions(),
        const SizedBox(height: 16),
        Text('Levels', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(child: _buildLevelsList()),
      ],
    );
  }

  Widget _buildRightPanelActions() {
    final compactButtonStyle = _rightPanelButtonStyle();

    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: compactButtonStyle,
            onPressed: _isBusy ? null : _handleSave,
            child: const Text('Save', maxLines: 1, softWrap: false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: compactButtonStyle,
            onPressed: _isBusy ? null : _handleOpen,
            child: const Text('Open', maxLines: 1, softWrap: false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: compactButtonStyle,
            onPressed: _isBusy ? null : _handleReveal,
            child: const Text('Reveal', maxLines: 1, softWrap: false),
          ),
        ),
      ],
    );
  }

  ButtonStyle _rightPanelButtonStyle() {
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(0, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildLevelsList() {
    final levels = _controller.availableLevels;
    if (levels.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text('No levels in current pack.'),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: levels.length,
      onReorder: _handleLevelsReorder,
      itemBuilder: (context, index) {
        final level = levels[index];
        final levelSize = _controller.levelGridSizeById(level.id);
        final levelSizePrefix = levelSize == null
            ? '?x?'
            : '${levelSize.width}x${levelSize.height}';
        final selected = level.id == _controller.currentLevelId;
        return Padding(
          key: ValueKey(level.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: selected ? Colors.indigo : Colors.black12),
            ),
            tileColor: selected ? Colors.indigo.withValues(alpha: 0.08) : null,
            title: Row(
              children: [
                if (_controller.isLevelChecked(level.id)) ...[
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text('$levelSizePrefix ${level.id}')),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Delete level',
                  onPressed: _isBusy ? null : () => _handleDeleteLevel(level.id),
                  icon: const Icon(Icons.delete_outline),
                ),
                ReorderableDragStartListener(
                  enabled: !_isBusy,
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
              ],
            ),
            onTap: _isBusy ? null : () => _handleLevelSwitch(level.id),
          ),
        );
      },
    );
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

enum _DirtyCreateLevelAction { save, discard, cancel }
