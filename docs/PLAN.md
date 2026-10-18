# Open Design Space: plan

An offline-first, open-source design tool for cutting machines, written in
Flutter. Every feature below answers a complaint in [RESEARCH.md](RESEARCH.md).

## Clean-room rule

The Electron app was studied only to learn its overall structure: an Electron
shell, separate front-end apps for home, login and the canvas, WASM engines for
the canvas, mat layout and tracing, and native add-ons for device I/O, fonts and
printing. **No code, assets, fonts, strings, file formats or protocols from it
are copied here.** `rea-output/` stays local and is git-ignored.

Talking to the machine directly is out of scope. The app exports open formats
(SVG, PDF, DXF, HPGL) and defines a `CutterDriver` interface so drivers can be
added as separate plugins later.

## Architecture

| Layer | Original (observed) | Open Design Space |
| --- | --- | --- |
| Shell | Electron main process + preload bridge | Flutter desktop/mobile/web, one codebase |
| UI | Separate web apps (home, login, canvas, tabs) | One app with Library, Canvas and Mat screens; no login |
| Canvas engine | WASM (`CriCanvas`) | Dart scene graph + `CustomPainter` |
| Geometry | Native `path-operation` add-on | Pure-Dart geometry (flatten, booleans, offset) |
| Mat layout | WASM (`PhysicalCanvas`) | Dart mat planner (manual + auto-pack) |
| Fonts | Native `system-fonts` | Bundled OFL fonts + user-imported TTF, outlined by a Dart TrueType parser |
| Storage | Cloud account | Local `.odsx` JSON files: autosave, snapshots, export |

## Features

### P0: nothing lost, nothing locked
- Local projects in an open JSON format, with no account, network or paywall.
- Autosave every few seconds plus crash recovery. Snapshot history per project.
- Project library with search, folders and favorites.
- Import SVG/PNG/JPG; export SVG/PDF/PNG/DXF/HPGL.
- Blank canvas on launch.

### P1: editing people asked for
- Shapes, text, images, freehand pen, multi-select (shift/cmd), layers panel.
- Move, resize, rotate, with a visible proportion-lock state. Snapping is a
  toggle (off by default).
- Weld, slice, intersect, subtract, crop, eraser, offset, flip, align and
  distribute.
- Node editing: drag, add and delete points.
- Text: real kerning/letter spacing, line spacing, curve text on multiple
  lines, convert to outlines on demand without destroying the original.
- Fast undo/redo (command stack) and full keyboard shortcuts.

### P2: making the cut
- Per-layer operation: cut, kiss cut, score, draw, print.
- Mat preview with mat size presets, one mat per color, free drag on the mat,
  a mat-order list, and an auto-pack toggle.
- Print then Cut: configurable printable area up to the full sheet,
  registration marks, PDF out.

## Milestones
1. Model, persistence, library and autosave.
2. Canvas, selection, transforms, layers and undo.
3. Geometry engine: booleans, offset, nodes, eraser, crop.
4. Text and fonts.
5. Mat planner and exporters.
6. Tests, polish, macOS build, GitHub release.

## Notes on the REA analysis

REA's static Electron analysis was run on the installed app bundle twice: with
the default 5-minute limit, then with a 30-minute limit and a 4 GB heap. Both
runs timed out on the app's 9 MB main-process bundle, after fully parsing 9 of
1,435 files. The architecture table above therefore comes mostly from the
bundle's file inventory (its folder layout, WASM modules and native add-on
names), not from REA's call graphs.
