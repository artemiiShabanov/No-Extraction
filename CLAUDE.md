# No-Extraction: working notes for Claude

Read `docs/DESIGN.md` before designing anything and `docs/PLAN.md` for scope. Design decisions
made in chat go into the decision log in `docs/DESIGN.md` the same day.

## Layout

- `scripts/` gameplay code, `scenes/` scenes, `shaders/`, `assets/models` glb from Blender,
  `assets/mixamo` rig + clips, `assets/env` CC0 textures (fetch: `tools/fetch_polyhaven.py`).
- `tools/blender/*.py` are the source of every model: edit the script, rebuild, never hand-edit glb.
- `debug/` debug menu, test scenes and playtest captures (`debug/playtest/` is gitignored).
- `docs/plan.yaml` is the plan source; `python3 tools/github/sync_plan.py --github` mirrors it.

## Verification loop

- Full run with aim bot and screenshots:
  `Godot --path . -- --auto-test --frames=900 --screenshot=<dir>/x.png` (prints INPUT/PERF/END);
  add `--gate-test` to force the gate to fall (breach + defeat), `--wave=N`, `--seed=N`.
- Hit zones + ragdoll: `Godot --path . res://debug/knight_test.tscn` must print `KNIGHT_TEST PASS`.
- Inspect an imported model: `Godot --headless --path . --script tools/godot/inspect_scene.gd -- res://...`.
- Rebuild models: `blender -b -P tools/blender/build_knight.py -- assets/models/knight.glb`.
- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`; run `--headless --import` after adding assets.

## Process

1. Pick an issue. If it needs a design decision, post a short brief on the issue first: the
   question, 2-3 options, a recommendation. Label `status: needs decision`. Wait for Artemii.
2. Implement on `main`, small commits, message references the issue (`#12`). Push.
3. When playable, label `status: needs playtest`, comment what to try and which debug tools help.
   Artemii plays, comments; iterate. Artemii closes the issue.
4. Definition of done: auto-test green, knight_test passes, a screenshot or measured number in
   the issue, decision log updated if anything was decided.

## Conventions

- GDScript with static typing; `var x := f()` fails when `f` returns Variant, type it explicitly.
- Godot front faces wind clockwise; Blender -Y exports to Godot +Z (scripts mirror Y).
- Mixamo clips are named `mixamo_com`; bones are `mixamorig_*`; import scale 100.
- Commit trailer: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
