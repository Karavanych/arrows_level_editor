import 'dart:io';

import 'package:arrows_level_editor/features/editor/model/editor_models.dart';
import 'package:arrows_level_editor/features/editor/persistence/alevelpack_storage_service.dart';
import 'package:arrows_level_editor/features/editor/persistence/editor_level_mapper.dart';
import 'package:arrows_level_editor/features/editor/persistence/level_id_generator.dart';
import 'package:arrows_level_editor/features/editor/persistence/model/alevelpack_models.dart';
import 'package:arrows_level_editor/features/editor/validation/editor_save_validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class EditorController extends ChangeNotifier {
  EditorController({
    ALevelPackStorageService? storageService,
    EditorLevelMapper? levelMapper,
    EditorSaveValidationService? saveValidationService,
    EditorLevelIdGenerator? levelIdGenerator,
  }) : _state = EditorState.initial(),
       _storageService = storageService ?? ALevelPackStorageService(),
       _levelMapper = levelMapper ?? const EditorLevelMapper(),
       _saveValidationService =
           saveValidationService ?? EditorSaveValidationService(),
       _levelIdGenerator = levelIdGenerator ?? EditorLevelIdGenerator(),
       _currentLevelId = (levelIdGenerator ?? EditorLevelIdGenerator())
           .generate() {
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lifecycleObserver._onAppDetached = () {
      saveCurrentLevelToDefaultPack();
    };
  }

  static const int _maxHistoryDepth = 3;

  EditorState _state;
  final ALevelPackStorageService _storageService;
  final EditorLevelMapper _levelMapper;
  final EditorSaveValidationService _saveValidationService;
  final EditorLevelIdGenerator _levelIdGenerator;
  final Set<int> _strokeTouchedCells = {};
  final Set<int> _eraseStrokeTouchedCells = {};
  final List<EditorStrokeChange> _undoHistory = [];
  final List<EditorStrokeChange> _redoHistory = [];
  final Map<int, EditorCell> _strokeBeforeCells = {};
  final Set<int> _strokeChangedCells = {};
  ALevelPackDocument? _openedPack;
  String _currentLevelId;
  String? _lastOpenedLevelId;
  SaveValidationResult? _lastSaveValidationResult;
  bool _isCurrentLevelDirty = false;
  final Map<String, EditorState> _levelDraftStates = {};
  final Map<String, bool> _levelDirtyStates = {};
  final Map<String, bool> _levelCheckedStates = {};
  final _EditorLifecycleObserver _lifecycleObserver = _EditorLifecycleObserver();

  EditorState get state => _state;
  String get currentLevelId => _currentLevelId;
  String? get lastOpenedLevelId => _lastOpenedLevelId;
  List<ALevelManifestEntry> get availableLevels =>
      _openedPack?.manifest.levels ?? const [];
  SaveValidationResult? get lastSaveValidationResult =>
      _lastSaveValidationResult;
  bool get isCurrentLevelDirty => _isCurrentLevelDirty;
  String? get currentPackName => _openedPack?.manifest.name;
  bool get isCurrentLevelCompletelyEmpty =>
      _state.cells.every(
        (cell) =>
            cell.paintColor == null &&
            !cell.isInactive &&
            !cell.hasStartMarker,
      );

  Future<void> createLevel({
    required int width,
    required int height,
  }) async {
    final safeWidth = width.clamp(1, 200);
    final safeHeight = height.clamp(1, 200);
    final nextLevelId = _levelIdGenerator.generate();
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
    _currentLevelId = nextLevelId;
    _isCurrentLevelDirty = true;
    _levelDirtyStates[_currentLevelId] = true;
    _levelCheckedStates[_currentLevelId] = false;
    _storeCurrentLevelDraft();

    final pack =
        _openedPack ??
        await _storageService.loadOrCreateDefaultPack(
          paletteColors: _state.paletteColors,
        );
    _openedPack = pack.ensureLevelEntry(nextLevelId);

    notifyListeners();
  }

  Future<void> recreateCurrentLevel({
    required int width,
    required int height,
  }) async {
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
    _strokeTouchedCells.clear();
    _eraseStrokeTouchedCells.clear();
    _isCurrentLevelDirty = true;
    _levelDirtyStates[_currentLevelId] = true;
    _levelCheckedStates[_currentLevelId] = false;
    _storeCurrentLevelDraft();

    final pack =
        _openedPack ??
        await _storageService.loadOrCreateDefaultPack(
          paletteColors: _state.paletteColors,
        );
    _openedPack = pack.ensureLevelEntry(_currentLevelId);

    notifyListeners();
  }

  Future<void> discardUnsavedChangesForCurrentLevel() async {
    await loadLevelFromDefaultPack(levelId: _currentLevelId);
  }

  Future<void> saveCurrentLevelToDefaultPack({
    String? levelId,
    bool skipValidation = true,
  }) async {
    final targetLevelId = levelId ?? _currentLevelId;
    final level = _levelMapper.toPersistedLevel(
      levelId: targetLevelId,
      state: _state,
      checked: _levelCheckedStates[targetLevelId] ?? false,
    );

    final existingPack =
        _openedPack ??
        await _storageService.loadOrCreateDefaultPack(
          paletteColors: _state.paletteColors,
        );
    final nextPack = _storageService.buildPackWithUpsertedLevel(
      source: existingPack,
      level: level,
      lastOpenedLevelId: targetLevelId,
    );

    final file = await _storageService.getDefaultPackFile();
    await _storageService.savePack(file: file, pack: nextPack);
    _openedPack = nextPack;
    _currentLevelId = targetLevelId;
    if (skipValidation) {
      _lastSaveValidationResult ??= const SaveValidationResult(
        problems: [],
        autoFixes: [],
      );
    } else {
      _lastSaveValidationResult = validateCurrentLevelBeforeSave();
    }
    _isCurrentLevelDirty = false;
    _levelDirtyStates[_currentLevelId] = false;
    _storeCurrentLevelDraft();
    notifyListeners();
  }

  Future<void> persistCurrentPackState() async {
    if (_openedPack == null) {
      return;
    }
    await saveCurrentLevelToDefaultPack();
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
      await createLevel(
        width: _state.gridSize.width,
        height: _state.gridSize.height,
      );
      return;
    }

    final targetLevelId =
        levelId ?? pack.manifest.lastOpenedLevelId ?? _currentLevelId;
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
    _restoreCheckedStatesFromPack(pack);
    _lastOpenedLevelId = selected.id;
    _currentLevelId = selected.id;
    _isCurrentLevelDirty = false;
    _levelDirtyStates[_currentLevelId] = false;
    _levelCheckedStates.putIfAbsent(_currentLevelId, () => false);
    _storeCurrentLevelDraft();
    notifyListeners();
  }

  Future<void> switchToLevel(String levelId) async {
    if (levelId == _currentLevelId) {
      return;
    }

    await persistCurrentPackState();
    _storeCurrentLevelDraft();
    _levelDirtyStates[_currentLevelId] = _isCurrentLevelDirty;

    final draftedState = _levelDraftStates[levelId];
    if (draftedState != null) {
      _state = draftedState;
      _undoHistory.clear();
      _redoHistory.clear();
      _strokeBeforeCells.clear();
      _strokeChangedCells.clear();
      _strokeTouchedCells.clear();
      _eraseStrokeTouchedCells.clear();
      _currentLevelId = levelId;
      _isCurrentLevelDirty = _levelDirtyStates[levelId] ?? true;
      _lastOpenedLevelId = levelId;
      notifyListeners();
      return;
    }

    await loadLevelFromDefaultPack(levelId: levelId);
  }

  Future<void> revealDefaultPackFolder() async {
    final file = await _storageService.getDefaultPackFile();
    final directory = Directory(file.parent.path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    if (Platform.isMacOS) {
      await Process.run('open', [directory.path]);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', [directory.path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [directory.path]);
      return;
    }
    throw UnsupportedError('Reveal is not supported on this platform.');
  }

  Future<void> deleteLevelById(String levelId) async {
    final pack =
        _openedPack ??
        await _storageService.loadOrCreateDefaultPack(
          paletteColors: _state.paletteColors,
        );
    final levels = pack.manifest.levels;
    final targetIndex = levels.indexWhere((entry) => entry.id == levelId);
    if (targetIndex < 0) {
      return;
    }
    final deletedCurrentLevel = levelId == _currentLevelId;

    final reducedPack = pack.removeLevel(levelId);
    _restoreCheckedStatesFromPack(reducedPack);
    _levelDraftStates.remove(levelId);
    _levelDirtyStates.remove(levelId);
    _levelCheckedStates.remove(levelId);

    if (reducedPack.manifest.levels.isEmpty) {
      _openedPack = reducedPack;
      await _persistPackDocument(
        reducedPack.copyWithManifest(clearLastOpenedLevelId: true),
      );
      await createLevel(
        width: _state.gridSize.width,
        height: _state.gridSize.height,
      );
      return;
    }

    if (deletedCurrentLevel) {
      final previousIndex = targetIndex - 1;
      final fallbackIndex = previousIndex >= 0 ? previousIndex : 0;
      final fallbackLevelId = reducedPack.manifest.levels[fallbackIndex].id;

      final draftedFallbackState = _levelDraftStates[fallbackLevelId];
      if (draftedFallbackState != null) {
        _state = draftedFallbackState.copyWith(
          cells: List<EditorCell>.from(draftedFallbackState.cells),
          paletteColors: List<Color>.from(draftedFallbackState.paletteColors),
        );
        _undoHistory.clear();
        _redoHistory.clear();
        _strokeBeforeCells.clear();
        _strokeChangedCells.clear();
        _strokeTouchedCells.clear();
        _eraseStrokeTouchedCells.clear();
      } else {
        ALevelPackLevel? fallbackLevel;
        for (final level in reducedPack.levels) {
          if (level.id == fallbackLevelId) {
            fallbackLevel = level;
            break;
          }
        }
        if (fallbackLevel != null) {
          _applyLoadedState(fallbackLevel);
        }
      }

      _currentLevelId = fallbackLevelId;
      _lastOpenedLevelId = fallbackLevelId;
      _isCurrentLevelDirty = _levelDirtyStates[fallbackLevelId] ?? false;
      _levelCheckedStates.putIfAbsent(fallbackLevelId, () => false);
      _storeCurrentLevelDraft();
    } else if (_lastOpenedLevelId == levelId) {
      _lastOpenedLevelId = _currentLevelId;
    }

    final persistedReducedPack = reducedPack.copyWithManifest(
      lastOpenedLevelId: _lastOpenedLevelId ?? _currentLevelId,
    );
    _openedPack = persistedReducedPack;
    await _persistPackDocument(persistedReducedPack);
    notifyListeners();
  }

  bool isLevelChecked(String levelId) => _levelCheckedStates[levelId] ?? false;

  void markCurrentLevelChecked(bool checked) {
    _levelCheckedStates[_currentLevelId] = checked;
    notifyListeners();
  }

  void clearCurrentLevelContents() {
    final width = _state.gridSize.width;
    final nextCells = List<EditorCell>.from(_state.cells);
    final changes = <CellChange>[];

    for (var index = 0; index < nextCells.length; index += 1) {
      final current = nextCells[index];
      if (current.paintColor == null &&
          !current.isInactive &&
          !current.hasStartMarker) {
        continue;
      }

      nextCells[index] = const EditorCell();
      changes.add(
        CellChange(
          x: index % width,
          y: index ~/ width,
          beforeCell: current,
          afterCell: const EditorCell(),
        ),
      );
    }

    if (changes.isEmpty) {
      return;
    }

    _state = _state.copyWith(cells: nextCells, clearSelectedCell: true);
    _undoHistory.add(EditorStrokeChange(changes: changes));
    _trimHistory(_undoHistory);
    _redoHistory.clear();
    _markCurrentLevelEdited();
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
    _markCurrentLevelEdited();
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
    _markCurrentLevelEdited();
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

  void _markCurrentLevelEdited() {
    _isCurrentLevelDirty = true;
    _levelDirtyStates[_currentLevelId] = true;
    _levelCheckedStates[_currentLevelId] = false;
    _storeCurrentLevelDraft();
  }

  void _storeCurrentLevelDraft() {
    _levelDraftStates[_currentLevelId] = _state.copyWith(
      cells: List<EditorCell>.from(_state.cells),
      paletteColors: List<Color>.from(_state.paletteColors),
    );
  }

  void _restoreCheckedStatesFromPack(ALevelPackDocument pack) {
    final next = <String, bool>{};
    for (final level in pack.levels) {
      next[level.id] = level.meta.checked;
    }
    _levelCheckedStates
      ..clear()
      ..addAll(next);
  }

  Future<void> _persistPackDocument(ALevelPackDocument pack) async {
    final file = await _storageService.getDefaultPackFile();
    await _storageService.savePack(file: file, pack: pack);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }
}

extension on ALevelPackDocument {
  ALevelPackDocument copyWithManifest({
    String? lastOpenedLevelId,
    bool clearLastOpenedLevelId = false,
  }) {
    return ALevelPackDocument(
      manifest: manifest.copyWith(
        lastOpenedLevelId: lastOpenedLevelId,
        clearLastOpenedLevelId: clearLastOpenedLevelId,
      ),
      palette: palette,
      levels: levels,
    );
  }
}

class _EditorLifecycleObserver with WidgetsBindingObserver {
  VoidCallback? _onAppDetached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _onAppDetached?.call();
    }
  }
}
