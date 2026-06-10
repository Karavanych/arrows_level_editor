# Reference Image Level Generator

## Purpose

`ReferenceImageLevelGenerator` is the dedicated generator class used by the `GENERATE LEVELS` button in the editor.

It is responsible for:

- reading reference images;
- converting each image into a new generated editor level;
- preserving the active/inactive mask from image transparency;
- turning large sampled color regions into more ribbon-like connected color structures.

This file describes the current implemented behavior in code, not an abstract future design.

Source:

- [reference_image_level_generator.dart](/Users/evkar/Dropbox/flatter/arrows_level_editor/lib/features/editor/reference_image_level_generator.dart)

## Entry Point

Main public entry:

- `generateLevelsFromReferenceImages(...)`

Behavior:

- takes a list of image file paths;
- takes current `gridWidth` and `gridHeight`;
- generates one `EditorState` per image;
- copies current palette/tool selection into the created levels;
- uses `_generateRibbonCells(...)` to build the board.

## High-Level Pipeline

For each image the generator currently does:

1. Sample the image into a grid.
2. Build color regions from neighboring similar sampled colors.
3. Initialize output grid as fully inactive.
4. Fill each region with multiple ribbon-like lines.
5. Fill any remaining active cells in that region with best-fit colors.
6. Repair same-color neighbor violations.
7. Enforce simple-path connected components.

## Stage 1. Image Sampling

Method:

- `_sampleImageCells(...)`

Rules:

- grid and image are matched proportionally by width and height independently;
- for each target grid cell, the code samples the image at the center of the corresponding image area;
- no averaging is used;
- no blur or palette approximation is used.

Transparency handling:

- if sampled pixel alpha is `0`, the cell becomes `inactive`;
- otherwise the sampled ARGB color becomes the initial active cell color.

Important current rule:

- source image transparency defines the active/inactive mask;
- transparent => inactive;
- non-transparent => active.

## Stage 2. Color Regions

Method:

- `_buildColorRegions(...)`

Rules:

- only non-inactive sampled cells participate;
- neighboring cells are grouped by 4-connectivity only:
  - left
  - right
  - up
  - down
- two neighbors belong to the same region if their color distance is within `regionColorTolerance`.

Each region stores:

- `indices`
- `baseColor`

`baseColor` is computed as the average color of the region.

## Stage 3. Ribbon Filling

Method:

- `_fillRegionWithRibbons(...)`

Goal:

- replace one large flat same-color region with several separate ribbon-like lines.

Current implemented strategy:

1. Estimate how many lines the region should have:
   - `lineCount ~= round(regionArea / targetCellsPerLine)`
   - clamp to `[1, maxLinesPerRegion]`
2. Choose multiple seed cells.
3. For each seed create a `_RibbonLine`.
4. Give each line a close color variant derived from the region base color.
5. Grow lines iteratively until they stop.

## Seed Selection

Method:

- `_chooseSeeds(...)`

Current strategy:

- sort cells by distance to region centroid;
- first seed is the cell nearest the centroid;
- next seeds are chosen to maximize distance from already chosen seeds;
- `seedSpacing` is used as a soft separation rule.

## Color Variants

Methods:

- `_variantColor(...)`
- `_repairColorVariants(...)`

Current strategy:

- lines in one region do not all use exactly the same color;
- nearby lines get close variants of the base region color;
- variants are created mainly by shifting value/lightness in HSV space;
- hue is mostly preserved;
- this helps separate lines visually while keeping the image’s overall color impression.

## Line Growth

Methods:

- `_bestGrowthCandidate(...)`
- `_scoreCandidate(...)`

Each `_RibbonLine` grows as a non-branching snake-like path.

Growth is attempted from both ends:

- head
- tail

A candidate cell is considered only if:

- it is inside the same region;
- it is not used yet;
- it does not already connect to too much of the same line;
- it does not violate the same-color neighbor rule.

### Candidate Scoring

Current scoring prefers:

- continuing straight when appropriate (`straightPreference`);
- sometimes turning (`turnPreference`);
- candidates with fewer surrounding active neighbors;
- candidates that do not create too many compact active blocks.

Current scoring penalizes:

- crowding near existing active cells (`sameFamilyCrowdingPenalty`);
- creating 2x2 active blocks (`blobPenalty`).

### Stop Conditions

A line can stop because:

- no valid candidate exists;
- it reached `maxLineLength`;
- it reached at least `minLineLength` and already passed `targetLineLength`, while the next candidate score is poor.

## Stage 4. Attach Leftovers

Method:

- `_attachLeftoversToRibbonEndpoints(...)`

Purpose:

- try to grow existing lines further into still-unused region cells;
- prefer attaching leftovers to line endpoints;
- avoid growing if it would strongly worsen blob structure or violate color-neighbor rules.

## Stage 5. Region Fill of Remaining Active Cells

Method:

- `_fillRemainingActiveRegionCells(...)`

Important current rule:

- active cells from the original sampled mask should remain active;
- the generator should not introduce new inactive holes inside originally active image regions.

If a cell belongs to an active region and is still inactive in the output after ribbon growth, the generator assigns it a color instead of leaving it inactive.

Current strategy:

1. Prefer colors already used by neighboring cells.
2. Otherwise try region color variants.
3. Otherwise try repair variants around the base color.
4. Otherwise choose a nearby color not already used by neighbors.

## Same-Color Neighbor Rule

Core method:

- `_wouldViolateSameColorNeighborRule(...)`

Current structural rule:

- no colored cell should end with more than 2 orthogonal neighbors of the exact same color.

Neighbors are counted only in 4 directions:

- left
- right
- up
- down

This rule is used during:

- line growth;
- leftover attachment;
- repair;
- recoloring.

Purpose:

- reduce same-color blobs;
- push exact-color components toward line-like structures;
- avoid branching and wide same-color masses.

## Stage 6. Repair Same-Color Violations

Method:

- `_repairSameColorNeighborViolations(...)`

If a cell still ends up with too many same-color neighbors:

- try recoloring it to one of several nearby repair variants;
- if that still fails, assign a nearest color not already used by neighbors.

This step tries to break exact same-color overcrowding without changing the active mask.

## Stage 7. Enforce Simple Path Components

Methods:

- `_buildExactColorComponents(...)`
- `_isSimplePathComponent(...)`
- `_enforceSimplePathComponents(...)`
- `_repairComponentTowardsPath(...)`

This is the strict path-validation stage for exact-color components.

Current target rule:

- each exact-color connected component should become a simple non-branching path of length at least 2.

That means:

- no singleton components;
- no cells with degree `0`;
- no cells with degree `> 2`;
- for length `2`, both cells should have degree `1`;
- for longer paths, exactly 2 endpoints should have degree `1`;
- all internal cells should have degree `2`.

### Repair Strategy

Current repair handles:

- singleton components:
  - try to recolor/attach them to a neighboring compatible color
- high-degree cells:
  - try to recolor the cell to a neighboring color
- components with too many endpoints:
  - recolor surplus endpoints
- components with too few endpoints:
  - recolor cells to break cycles or invalid structures

This repair is local and heuristic, not a full graph-theoretic optimizer.

## Configurable Parameters

Class:

- `ReferenceImageGenerationConfig`

Current parameters:

- `targetCellsPerLine = 10`
- `minLineLength = 4`
- `targetLineLength = 8`
- `maxLineLength = 16`
- `maxLinesPerRegion = 8`
- `seedSpacing = 3`
- `turnPreference = 0.35`
- `straightPreference = 0.55`
- `blobPenalty = 1.0`
- `sameFamilyCrowdingPenalty = 0.7`
- `variantLightnessStep = 0.08`
- `regionColorTolerance = 24`
- `cleanupPasses = 2`

These are the main levers for tuning generator behavior.

## Current Guarantees / Intent

The current implementation is trying to achieve:

- preserve image transparency as inactive mask;
- preserve rough regional color impression from the source image;
- avoid large exact-color flat blobs;
- produce more ribbon-like same-color components;
- enforce non-branching simple-path exact-color structures where possible.

## Current Limitations

The current generator is still heuristic and not final.

Known limitations by design:

- it does not understand gameplay difficulty yet;
- it does not guarantee good start-point placement by itself;
- it does not guarantee interesting final move order;
- color repair may drift from the exact original sampled color when needed to preserve structure;
- region segmentation is still local and tolerance-based, not semantic image understanding.

## Relationship To The Editor UI

The generator must stay separate from UI code.

Current intended ownership:

- `editor_screen.dart` triggers generation;
- `ReferenceImageLevelGenerator` owns the image-to-level transformation logic.

This keeps the UI thin and makes the algorithm easier to tune separately.
