# PROJECT ARCHITECTURE INDEX

Standalone Flutter desktop-first prototype for a paint-like arrows level grid editor. Editor-first workflow: no save/export format locked yet, no runtime puzzle logic, no external packages beyond Flutter SDK defaults.

## Entry Point

**lib/main.dart**
- Role: Application bootstrap
- Responsibilities:
  - Call `runApp` with `ArrowsLevelEditorApp`

## App Configuration

**lib/app/app.dart** — `ArrowsLevelEditorApp`
- Role: Root app shell
- Responsibilities:
  - Configure `MaterialApp`
  - Set `EditorScreen` as `home`
  - Provide base Material theme
- Notes: no app-specific routing or service layer

**pubspec.yaml**
- Role: Package manifest
- Responsibilities:
  - Flutter app metadata and SDK constraints
  - Only lightweight default deps: `flutter`, `cupertino_icons`
- Notes: no third-party color picker, persistence, or state-management packages

## Plan / Intent

**EDITOR_PLAN.md**
- Role: Product and build plan
- Responsibilities:
  - Documents editor-first approach
  - Captures V1 UX rules, tool behavior, palette direction, and deferred save-format decision
  - Notes key interaction rules such as right-click clear and Flutter as the chosen stack
- Notes: authoritative planning doc; implementation has already advanced beyond early plan snapshots

## Core Models / State

**lib/features/editor/model/editor_models.dart**
- Role: Immutable editor domain and history models
- Responsibilities:
  - `EditorGridSize` — width/height
  - `EditorCell` — per-cell `paintColor`, `isInactive`, `hasStartMarker`
  - `CellChange` — one cell history diff with `x`, `y`, `beforeCell`, `afterCell`
  - `EditorStrokeChange` — one committed stroke history entry
  - `EditorTool` enum — `paint`, `inactive`, `startMarker`, `erase`
  - `EditorState` — grid size, flat cells, selected color, selected tool, fixed palette, optional selected cell
- Notes:
  - `select` tool has been removed
  - Palette is fixed to 24 colors
  - State is still cell-based only; no line objects yet

**lib/features/editor/state/editor_controller.dart** — `EditorController`
- Role: Mutable editor logic via `ChangeNotifier`
- Responsibilities:
  - Hold authoritative `EditorState`
  - Grid lifecycle: `generateGrid`
  - Tool/color selection: `selectTool`, `selectColor`, `selectColorAndActivatePaint`
  - Stroke lifecycle:
    - left/edit stroke: `beginStroke`, `touchCell`, `endStroke`
    - right/erase stroke: `beginEraseStroke`, `eraseCell`, `endEraseStroke`
  - Cell mutation:
    - `updateCell`
    - `clearCell`
    - `selectCell`
  - Undo/redo:
    - `undo()`
    - `redo()`
    - history depth capped to 3 undo + 3 redo entries
- Behavior rules currently enforced:
  - `paint` only applies to empty cells
  - `inactive` only applies to empty cells and produces a clean inactive cell
  - right-click clear fully resets the cell
  - `startMarker` is applied through its own tool path
  - each history step is one completed mouse stroke, not each touched cell

## Main Screen / Interaction Orchestration

**lib/features/editor/editor_screen.dart** — `EditorScreen`
- Role: Main editor UI and keyboard orchestration
- Responsibilities:
  - Own `EditorController`
  - Own width/height text controllers
  - Own editor `FocusNode`
  - Layout:
    - left tool/palette panel
    - center grid canvas
    - right debug/state panel
  - Wire Generate button to `generateGrid`
  - Render tool chips for `paint`, `inactive`, `startMarker`, `erase`
  - Render 24-color palette as a 4x6 grid
  - Palette click:
    - sets selected color
    - auto-activates `paint`
  - Handle direct desktop keyboard shortcuts on the editor focus node:
    - macOS: `Cmd+Z`, `Cmd+Shift+Z`
    - Windows/Linux: `Ctrl+Z`, `Ctrl+Shift+Z`, `Ctrl+Y`
- Notes:
  - Shortcut handling is implemented directly in `onKeyEvent`, not via `Shortcuts/Actions`
  - Ignores editor-level undo/redo while an `EditableText` has primary focus
  - Grid interaction explicitly requests editor focus so shortcuts work after canvas use

## Grid Canvas / Viewport / Pointer Logic

**lib/features/editor/widgets/editor_grid_view.dart** — `EditorGridView` + `_GridPainter`
- Role: Single-surface interactive board canvas
- Responsibilities:
  - Render cells, borders, inactive cross overlay, and start marker overlay via `CustomPaint`
  - Maintain viewport transform:
    - `_scale`
    - `_offset`
  - Support zoom/pan:
    - mouse wheel zoom
    - trackpad pan/zoom
    - touch pinch/pan
    - modifier-drag pan
  - Support input modes:
    - left drag => active tool stroke
    - right drag => global full-cell clear
    - `Ctrl`/`Cmd` + left/right drag => pan viewport
  - Support field color picking:
    - only in `paint` mode
    - only on a true click on a painted cell
    - no pick on drag, inactive cells, or other tools
  - Recenter/clamp viewport when grid changes
- Notes:
  - Right-click erase has priority over the selected tool
  - Color pick from field routes through `onColorPick`, which activates `paint`
  - Uses one painter surface rather than a widget-per-cell grid

## Current UX Rules Reflected In Code

- Width/height are numeric inputs, applied by `Generate`
- Palette is a fixed 24-color grid
- Clicking a palette swatch also activates `paint`
- `select` tool removed from UI and model
- Right mouse button always fully clears cell state:
  - paint color
  - inactive flag
  - start marker
- `paint` and `inactive` do not overwrite occupied cells
- To replace existing content, the user must clear first
- `inactive` is a final cell state, not a visual overlay on top of paint
- True-click on a painted field cell in `paint` mode picks that color
- Undo/redo history is stroke-based and capped to 3 levels each

## Debug / Inspection

- Right-side panel shows:
  - grid size
  - selected tool
  - selected color
  - counts for painted / inactive / marker cells
  - selected cell details
  - compact internal preview of edited cells
- This is currently part of normal prototype inspection, not gameplay logic

## Tests

**test/widget_test.dart**
- Role: Basic widget smoke test scaffold
- Notes: not yet a strong interaction regression suite for editor behavior

## Platform / Build Notes

- Standard Flutter multi-platform scaffold present: `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`
- Current practical target: desktop-first, especially macOS and Windows
- Mobile compatibility is a future-friendly goal, not a polished target yet
- Run locally with `flutter run -d macos` or another Flutter device target

## Not Implemented Yet

- Final authoring/save format
- Export/import pipeline
- Runtime line-path object model
- Puzzle validation rules
- Dead-start detection
- Persistent project files
- Undo/redo UI buttons
- Dedicated tests for pointer and keyboard interaction flows

## Source Layout Summary

```text
lib/
  main.dart
  app/app.dart
  features/editor/
    editor_screen.dart
    model/editor_models.dart
    state/editor_controller.dart
    widgets/editor_grid_view.dart
```
