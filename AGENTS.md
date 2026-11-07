# Notes for AI agents

Read [CONTRIBUTING.md](CONTRIBUTING.md): it has the repository layout, the rules and the investigation method.

- Nothing derived from the game goes in here: executable, generated code, shaders, caches, saves or dumps. `tools/check_content.py` checks this.
- Work only with your own copy of the game. If you do not have one, stop. Do not explain how to obtain a game or keys.
- Never edit `generated/` by hand: use `recomp/patches.py` or `tools/oot/patch_generated.py`.
- Do not use `--no-verify`. Work on a branch and merge it into `main` once it builds, passes the tests that cover the
  change and has been run in game: `main` is the line that is known to work (CONTRIBUTING.md, "Branches").
- Tests open a window: use `GHF_INPUT=none` so the person's keyboard does not disturb the game.
- This project is Linux-only and English-only. Do not add `.bat`, `.ps1`, `.exe`, installer windows or Portuguese text
  back; write new user-facing strings in English and new paths in ASCII. The Windows platform layer is gone: the host
  back ends are `runtime/platform/linux.c` and the `*_sdl.*` files, so a new host adds a platform file rather than a
  `_win` twin. `runtime/greenhatflute.ico` is not a Windows leftover -- `tools/install_linux.py` reads the PNG sizes
  stored inside it.
- Docs describe this build in its own terms. Where the project came from is in the README's Credits and in
  `THIRD_PARTY_NOTICES.md`; do not explain a design by what some other project did.
