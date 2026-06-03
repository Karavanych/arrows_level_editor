import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:flutter/material.dart';

class EditorController extends ChangeNotifier {
  EditorController() : _state = EditorState.initial();

  EditorState _state;
  final Set<int> _strokeTouchedCells = {};
  final Set<int> _eraseStrokeTouchedCells = {};

  EditorState get state => _state;

  void generateGrid({required int width, required int height}) {
    final safeWidth = width.clamp(1, 200);
    final safeHeight = height.clamp(1, 200);
    _state = _state.copyWith(
      gridSize: EditorGridSize(width: safeWidth, height: safeHeight),
      cells: List<EditorCell>.filled(
        safeWidth * safeHeight,
        const EditorCell(),
      ),
      clearSelectedCell: true,
    );
    notifyListeners();
  }

  void selectTool(EditorTool tool) {
    _state = _state.copyWith(selectedTool: tool);
    notifyListeners();
  }

  void selectColor(Color color) {
    _state = _state.copyWith(selectedColor: color);
    notifyListeners();
  }

  void beginStroke(int index) {
    _strokeTouchedCells.clear();
    touchCell(index);
  }

  void touchCell(int index) {
    if (!_strokeTouchedCells.add(index)) {
      return;
    }
    updateCell(index);
  }

  void endStroke() {
    _strokeTouchedCells.clear();
  }

  void beginEraseStroke(int index) {
    _eraseStrokeTouchedCells.clear();
    eraseCell(index);
  }

  void eraseCell(int index) {
    if (!_eraseStrokeTouchedCells.add(index)) {
      return;
    }
    clearCell(index);
  }

  void endEraseStroke() {
    _eraseStrokeTouchedCells.clear();
  }

  void clearCell(int index) {
    if (index < 0 || index >= _state.cells.length) {
      return;
    }

    final current = _state.cells[index];
    if (current.paintColor == null &&
        !current.isInactive &&
        !current.hasStartMarker) {
      return;
    }

    final nextCells = List<EditorCell>.from(_state.cells);
    nextCells[index] = const EditorCell();
    _state = _state.copyWith(cells: nextCells, selectedCellIndex: index);
    notifyListeners();
  }

  void selectCell(int index) {
    if (index < 0 || index >= _state.cells.length) {
      return;
    }
    _state = _state.copyWith(selectedCellIndex: index);
    notifyListeners();
  }

  void updateCell(int index) {
    if (index < 0 || index >= _state.cells.length) {
      return;
    }

    if (_state.selectedTool == EditorTool.select) {
      selectCell(index);
      return;
    }

    final current = _state.cells[index];
    late final EditorCell updated;

    switch (_state.selectedTool) {
      case EditorTool.paint:
        updated = current.copyWith(
          paintColor: _state.selectedColor,
          isInactive: false,
        );
      case EditorTool.inactive:
        updated = const EditorCell(isInactive: true);
      case EditorTool.startMarker:
        updated = current.copyWith(hasStartMarker: true);
      case EditorTool.erase:
        updated = const EditorCell();
      case EditorTool.select:
        updated = current;
    }

    final nextCells = List<EditorCell>.from(_state.cells);
    nextCells[index] = updated;
    _state = _state.copyWith(cells: nextCells, selectedCellIndex: index);
    notifyListeners();
  }
}
