# Notes for AI agents

Read [CONTRIBUTING.md](CONTRIBUTING.md): it has the repository layout, the rules and the investigation method.

- Nothing derived from the game goes in here: executable, generated code, shaders, caches, saves or dumps. `tools/check_content.py` checks this.
- Work only with your own copy of the game. If you do not have one, stop. Do not explain how to obtain a game or keys.
- Never edit `generated/` by hand: use `recomp/patches.py` or `tools/oot/patch_generated.py`.
- Do not use `--no-verify`, and do not push straight to `main`.
- Tests open a window: use `TOTK_INPUT=none` so the person's keyboard does not disturb the game.
- This fork is Linux-only and English-only. Do not add `.bat`, `.ps1`, `.exe`, installer windows or Portuguese text back;
  write new user-facing strings in English and new paths in ASCII. The Windows runtime files (`runtime/platform/win32.c`,
  `runtime/*_win.c`, `runtime/totk.rc`) are still in the tree as the platform layer's other half — leave them unless the
  maintainer says otherwise.
