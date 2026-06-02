# PROJECT ARCHITECTURE INDEX

Standalone Flutter desktop-first prototype for a paint-like arrows level grid editor. No save/export, no persistence, no external packages beyond Flutter SDK defaults.

## Entry Point

**lib/main.dart**
- Role: Application bootstrap
- Responsibilities:
  - Call `runApp` with `ArrowsLevelEditorApp`
- Notes: No window manager or platform-specific startup logic

## App Configuration

**lib/app/app.dart** — `ArrowsLevelEditorApp`
- Role: Root app shell
- Responsibilities:
  - Configure `MaterialApp` (title, theme, home)
  - Material 3 theme via `ColorScheme.fromSeed` (indigo)
  - Set `EditorScreen` as `home`
- Notes: `debugShowCheckedModeBanner` disabled

**pubspec.yaml**
- Role: Package manifest and dependency constraints
- Responsibilities:
  - Package name `arrows_level_editor`
  - Dart SDK `^3.10.0` (compatible with Flutter 3.38.x / Dart 3.10.4)
  - Dependencies: `flutter`, `cupertino_icons` only
  - Dev: `flutter_test`, `flutter_lints`
- Notes: No assets, fonts, or third-party editor packages declared

## Plan / Status Document

**EDITOR_PLAN.md**
- Role: Product and build plan (v0.1)
- Responsibilities:
  - Defines editor-first goals, V1 scope, editing modes, color system, build stages, success criteria
  - Documents open design question: cell-paint vs line-as-object model
  - Recommends Flutter for tool-like UI; defers save format decision
- Notes: Authoritative intent doc; not all “nice to have” items are implemented in code yet

## Core Models / State

**lib/features/editor/model/editor_models.dart**
- Role: Editor domain types and immutable aggregate state
- Responsibilities:
  - `EditorGridSize` — width/height of the field
  - `EditorCell` — per-cell `paintColor`, `isInactive`, `hasStartMarker` with `copyWith`
  - `EditorTool` enum — `paint`, `inactive`, `startMarker`, `erase`, `select`
  - `EditorState` — grid size, flat `cells` list, selected color/tool, preset `paletteColors`, optional `selectedCellIndex`
  - `EditorState.initial` — default 10×10 empty grid and built-in palette
- Notes: Cell-based model only; no line objects or route validation

**lib/features/editor/state/editor_controller.dart** — `EditorController`
- Role: Mutable editor logic (`ChangeNotifier`)
- Responsibilities:
  - Hold authoritative `EditorState`
  - `generateGrid` — recreate cells on Generate (clamp 1–200, clear selection)
  - `selectTool`, `selectColor`
  - Stroke API: `beginStroke`, `touchCell`, `endStroke` with per-stroke dedup set
  - `updateCell` — apply current tool to a cell index
  - `selectCell` — used from select tool path
- Notes: No undo/redo, no file I/O, no palette mutation API; does not own viewport zoom/pan

## Features

**lib/features/editor/editor_screen.dart** — `EditorScreen`
- Role: Main editor UI and layout orchestration
- Responsibilities:
  - Own `EditorController` and width/height `TextEditingController`s
  - Three-column layout: left toolbar (280px), center canvas, right debug panel (250px)
  - Wire Generate to `generateGrid`
  - Tool selector (`ChoiceChip` per `EditorTool`)
  - Color palette taps → `selectColor`
  - Pass stroke callbacks into `EditorGridView`
  - Debug / state preview panel (counts, selected cell, truncated edited-cells preview)
- Notes:
  - Left panel uses `SingleChildScrollView` for toolbar only; center grid does not scroll
  - “Add/Edit Color” button is disabled with TODO for color picker
  - UI helpers (`_toolLabel`, `_colorLabel`, `_statePreview`) live in this file

## Widgets / UI

**lib/features/editor/widgets/editor_grid_view.dart** — `EditorGridView` + `_GridPainter`
- Role: Single-surface grid canvas with unified viewport navigation and painting
- Responsibilities:
  - Render the full board via one `CustomPaint` / `_GridPainter` (cells, borders, inactive cross, start marker, selection) — no `GridView`, no nested scroll for navigation
  - Viewport state: `_scale`, `_offset`, `_viewportSize`; transform applied inside painter (`canvas.translate` / `canvas.scale`)
  - Zoom limits: min `0.2`, max `2.2`; wheel step `_wheelZoomStep`
  - Input:
    - Desktop: `PointerScrollEvent` for mouse wheel zoom at cursor
    - macOS trackpad: `PointerPanZoomStart` / `PointerPanZoomUpdate` for pinch + pan
    - Mobile/tablet: `GestureDetector` scale gestures (multi-touch pinch/pan)
    - Single pointer: paint/drag via `onStrokeStart` / `onCellDrag` / `onStrokeEnd`
    - Multi-pointer: viewport navigation only
  - Hit-test: `_indexFromViewportPosition` maps viewport coords → scene → cell index (same math as paint transform)
  - Pan clamp: center-based model (`_clampAxisOffset`) — viewport center in scene coords stays within board `[0, boardSize]`; allows visible empty space near edges but board cannot leave the screen; not hard edge-pinned to viewport
  - On grid size change (`Generate`): re-center board via `_centeredOffset` when `gridKey` changes
  - Cull off-screen cells in painter using visible scene bounds
- Notes:
  - Board background is white over full board rect in scene space (avoids gray viewport bleed on large grids)
  - Gray `0xFFF5F5F5` is only the outer `EditorScreen` container around the canvas area

## Tests

**test/widget_test.dart**
- Role: Widget smoke test
- Responsibilities:
  - Pump `ArrowsLevelEditorApp`
  - Assert presence of title, Generate, and State Preview labels
- Notes: No interaction, zoom, or grid-editing coverage

## Platform / Build Notes

- Standard Flutter multi-platform scaffold (`android/`, `ios/`, `macos/`, `web/`, `windows/`, `linux/`) — generated boilerplate, not customized for editor logic
- Target platforms per plan: macOS and Windows desktop-first; mobile possible later
- Run: `flutter pub get` then `flutter run -d macos` (or other device)
- **Not implemented:** save/export/import, undo/redo, custom color picker, line validation, connected-region detection
- **Prototype status:** Stages 1–3, viewport navigation (zoom/pan), and partial Stage 4 from `EDITOR_PLAN.md`; Stage 5 (save format) not started

## Source Layout Summary

```
lib/
  main.dart
  app/app.dart
  features/editor/
    editor_screen.dart
    model/editor_models.dart
    state/editor_controller.dart
    widgets/editor_grid_view.dart
```
