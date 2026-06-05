import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/persistence/alevelpack_storage_service.dart';
import 'package:arrows_level_editor/features/editor/persistence/editor_level_mapper.dart';
import 'package:arrows_level_editor/features/editor/persistence/model/alevelpack_models.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_save_validation.dart';
import 'package:flutter/material.dart';

class EditorController extends ChangeNotifier {
  EditorController({
    ALevelPackStorageService? storageService,
    EditorLevelMapper? levelMapper,
    EditorSaveValidationService? saveValidationService,
  }) : _state = EditorState.initial(),
       _storageService = storageService ?? ALevelPackStorageService(),
       _levelMapper = levelMapper ?? const EditorLevelMapper(),
       _saveValidationService =
           saveValidationService ?? EditorSaveValidationService();

  static const int _maxHistoryDepth = 3;

  EditorState _state;
  final ALevelPackStorageService _storageService;
  final EditorLevelMapper _levelMapper;
  final EditorSaveValidationService _saveValidationService;
  final Set<int> _strokeTouchedCells = {};
  final Set<int> _eraseStrokeTouchedCells = {};
  final List<EditorStrokeChange> _undoHistory = [];
  final List<EditorStrokeChange> _redoHistory = [];
  final Map<int, EditorCell> _strokeBeforeCells = {};
  final Set<int> _strokeChangedCells = {};
  ALevelPackDocument? _openedPack;
  String _currentLevelId = 'level_001';
  String? _lastOpenedLevelId;
  SaveValidationResult? _lastSaveValidationResult;
  bool _isCurrentLevelDirty = false;

  EditorState get state => _state;
  String get currentLevelId => _currentLevelId;
  String? get lastOpenedLevelId => _lastOpenedLevelId;
  List<ALevelManifestEntry> get availableLevels =>
      _openedPack?.manifest.levels ?? const [];
  SaveValidationResult? get lastSaveValidationResult =>
      _lastSaveValidationResult;
  bool get isCurrentLevelDirty => _isCurrentLevelDirty;
  String? get currentPackName => _openedPack?.manifest.name;

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
    _undoHistory.clear();
    _redoHistory.clear();
    _strokeBeforeCells.clear();
    _strokeChangedCells.clear();
    _isCurrentLevelDirty = true;
    notifyListeners();
  }

  Future<void> saveCurrentLevelToDefaultPack({
    String? levelId,
    bool skipValidation = false,
  }) async {
    final validation = skipValidation
        ? (_lastSaveValidationResult ??
              const SaveValidationResult(problems: [], autoFixes: []))
        : validateCurrentLevelBeforeSave();
    if (!skipValidation && validation.hasBlockingProblems) {
      return;
    }

    final targetLevelId = levelId ?? _currentLevelId;
    final level = _levelMapper.toPersistedLevel(
      levelId: targetLevelId,
      state: _state,
    );

    final existingPack = await _storageService.loadOrCreateDefaultPack(
      paletteColors: _state.paletteColors,
    );
    final nextPack = _storageService.buildPackWithUpsertedLevel(
      source: existingPack,
      level: level,
    );

    final file = await _storageService.getDefaultPackFile();
    await _storageService.savePack(file: file, pack: nextPack);
    _openedPack = nextPack;
    _currentLevelId = targetLevelId;
    _lastSaveValidationResult = validation;
    _isCurrentLevelDirty = false;
    notifyListeners();
  }

  SaveValidationResult validateCurrentLevelBeforeSave() {
    final result = _saveValidationService.validate(_state);
    _lastSaveValidationResult = result;
    notifyListeners();
    return result;
  }

  SaveValidationResult applyAutoFixAndRevalidate(
    SaveValidationAutoFixType autoFixType,
  ) {
    final beforeState = _state;
    _state = _saveValidationService.applyAutoFix(
      state: _state,
      autoFixType: autoFixType,
    );
    _undoHistory.clear();
    _redoHistory.clear();
    _strokeBeforeCells.clear();
    _strokeChangedCells.clear();
    _strokeTouchedCells.clear();
    _eraseStrokeTouchedCells.clear();

    final result = _saveValidationService.validate(_state);
    _lastSaveValidationResult = result;
    if (!_statesEqual(beforeState, _state)) {
      _isCurrentLevelDirty = true;
    }
    notifyListeners();
    return result;
  }

  Future<void> loadLevelFromDefaultPack({String? levelId}) async {
    final pack = await _storageService.loadOrCreateDefaultPack(
      paletteColors: _state.paletteColors,
    );
    if (pack.levels.isEmpty) {
      _openedPack = pack;
      _isCurrentLevelDirty = false;
      notifyListeners();
      return;
    }

    final targetLevelId = levelId ?? _currentLevelId;
    ALevelPackLevel? selected;
    for (final level in pack.levels) {
      if (level.id == targetLevelId) {
        selected = level;
        break;
      }
    }
    selected ??= pack.levels.first;

    _applyLoadedState(selected);
    _openedPack = pack;
    _lastOpenedLevelId = selected.id;
    _currentLevelId = selected.id;
    _isCurrentLevelDirty = false;
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

  void selectColorAndActivatePaint(Color color) {
    _state = _state.copyWith(
      selectedColor: color,
      selectedTool: EditorTool.paint,
    );
    notifyListeners();
  }

  void beginStroke(int index) {
    _strokeTouchedCells.clear();
    _beginHistoryStroke();
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
    _commitHistoryStroke();
  }

  void beginEraseStroke(int index) {
    _eraseStrokeTouchedCells.clear();
    _beginHistoryStroke();
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
    _commitHistoryStroke();
  }

  void undo() {
    if (_undoHistory.isEmpty) {
      return;
    }

    final stroke = _undoHistory.removeLast();
    final nextCells = List<EditorCell>.from(_state.cells);
    int? selectedIndex;
    for (final change in stroke.changes) {
      final index = _indexFromCoordinates(change.x, change.y);
      if (index == null) {
        continue;
      }
      nextCells[index] = change.beforeCell;
      selectedIndex = index;
    }

    _state = _state.copyWith(
      cells: nextCells,
      selectedCellIndex: selectedIndex,
    );
    _redoHistory.add(stroke);
    _trimHistory(_redoHistory);
    notifyListeners();
  }

  void redo() {
    if (_redoHistory.isEmpty) {
      return;
    }

    final stroke = _redoHistory.removeLast();
    final nextCells = List<EditorCell>.from(_state.cells);
    int? selectedIndex;
    for (final change in stroke.changes) {
      final index = _indexFromCoordinates(change.x, change.y);
      if (index == null) {
        continue;
      }
      nextCells[index] = change.afterCell;
      selectedIndex = index;
    }

    _state = _state.copyWith(
      cells: nextCells,
      selectedCellIndex: selectedIndex,
    );
    _undoHistory.add(stroke);
    _trimHistory(_undoHistory);
    notifyListeners();
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
    _recordCellChange(index, current);
    _isCurrentLevelDirty = true;
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

    final current = _state.cells[index];
    final isEmptyForPaintOrInactive =
        current.paintColor == null && !current.isInactive;
    late final EditorCell updated;

    switch (_state.selectedTool) {
      case EditorTool.paint:
        if (!isEmptyForPaintOrInactive) {
          return;
        }
        updated = current.copyWith(
          paintColor: _state.selectedColor,
          isInactive: false,
        );
      case EditorTool.inactive:
        if (!isEmptyForPaintOrInactive) {
          return;
        }
        updated = const EditorCell(isInactive: true);
      case EditorTool.startMarker:
        updated = current.copyWith(hasStartMarker: true);
      case EditorTool.erase:
        updated = const EditorCell();
    }

    final nextCells = List<EditorCell>.from(_state.cells);
    nextCells[index] = updated;
    _state = _state.copyWith(cells: nextCells, selectedCellIndex: index);
    _recordCellChange(index, current);
    _isCurrentLevelDirty = true;
    notifyListeners();
  }

  void _beginHistoryStroke() {
    _strokeBeforeCells.clear();
    _strokeChangedCells.clear();
  }

  void _commitHistoryStroke() {
    if (_strokeChangedCells.isEmpty) {
      _strokeBeforeCells.clear();
      return;
    }

    final width = _state.gridSize.width;
    final changes = <CellChange>[];
    for (final index in _strokeChangedCells) {
      final before = _strokeBeforeCells[index];
      if (before == null) {
        continue;
      }
      final after = _state.cells[index];
      if (_cellsEqual(before, after)) {
        continue;
      }
      changes.add(
        CellChange(
          x: index % width,
          y: index ~/ width,
          beforeCell: before,
          afterCell: after,
        ),
      );
    }

    _strokeBeforeCells.clear();
    _strokeChangedCells.clear();
    if (changes.isEmpty) {
      return;
    }

    _undoHistory.add(EditorStrokeChange(changes: changes));
    _trimHistory(_undoHistory);
    _redoHistory.clear();
  }

  void _recordCellChange(int index, EditorCell beforeCell) {
    _strokeBeforeCells.putIfAbsent(index, () => beforeCell);
    _strokeChangedCells.add(index);
  }

  int? _indexFromCoordinates(int x, int y) {
    final width = _state.gridSize.width;
    final height = _state.gridSize.height;
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return null;
    }
    return (y * width) + x;
  }

  bool _cellsEqual(EditorCell a, EditorCell b) {
    final aColor = a.paintColor;
    final bColor = b.paintColor;
    return aColor?.toARGB32() == bColor?.toARGB32() &&
        a.isInactive == b.isInactive &&
        a.hasStartMarker == b.hasStartMarker;
  }

  bool _statesEqual(EditorState a, EditorState b) {
    if (a.gridSize.width != b.gridSize.width ||
        a.gridSize.height != b.gridSize.height) {
      return false;
    }
    if (a.cells.length != b.cells.length) {
      return false;
    }
    for (var i = 0; i < a.cells.length; i += 1) {
      if (!_cellsEqual(a.cells[i], b.cells[i])) {
        return false;
      }
    }
    return true;
  }

  void _trimHistory(List<EditorStrokeChange> history) {
    while (history.length > _maxHistoryDepth) {
      history.removeAt(0);
    }
  }

  void _applyLoadedState(ALevelPackLevel level) {
    _state = _levelMapper.fromPersistedLevel(
      level: level,
      paletteColors: _state.paletteColors,
      selectedColor: _state.selectedColor,
      selectedTool: _state.selectedTool,
    );
    _undoHistory.clear();
    _redoHistory.clear();
    _strokeBeforeCells.clear();
    _strokeChangedCells.clear();
    _strokeTouchedCells.clear();
    _eraseStrokeTouchedCells.clear();
  }
}
