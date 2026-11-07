#!/usr/bin/env python3
"""Installs the Linux desktop entry: an app-launcher icon, a menu entry, and a command on PATH.

Nothing in the build changes; this only writes the three files a desktop session reads:

  ~/.local/share/applications/ocarina-recomp.desktop   from jogar/ocarina-recomp.desktop, with the launcher's path
  ~/.local/share/icons/hicolor/<N>x<N>/apps/ocarina-recomp.png   the sizes carried in runtime/totk.ico
  ~/.local/bin/ocarina-recomp                          a link to jogar/jogar-ocarina.sh

XDG paths are used, so no root is needed and nothing is written under /usr. The app id the game sets on Wayland
(gfx_window_sdl.c) is "ocarina-recomp", which is what the .desktop file is named after: the session then groups the
window under this entry instead of showing an unnamed window.

Run: python tools/install_linux.py [--uninstall] [--dry-run] [--home DIR] [--bin DIR]
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = 'ocarina-recomp'
ICO = ROOT / 'runtime' / 'totk.ico'
DESKTOP = ROOT / 'jogar' / f'{APP}.desktop'
LAUNCHER = ROOT / 'jogar' / 'jogar-ocarina.sh'


def ico_pngs(path: Path) -> dict[int, bytes]:
    """The PNG images an .ico carries, keyed by their edge in pixels.

    A modern .ico stores each size as a whole PNG, so no image library is needed to read it: the icon directory is a
    header, one 16-byte entry per image, then the images. Older files store BMPs instead; those are skipped rather
    than converted, since hicolor wants PNG and the game's icon carries PNGs at every size.
    """
    data = path.read_bytes()
    if len(data) < 6:
        raise SystemExit(f'{path}: too small to be an icon')
    reserved, kind, count = struct.unpack('<HHH', data[:6])
    if reserved or kind != 1:
        raise SystemExit(f'{path}: not an .ico (reserved {reserved}, type {kind})')
    out: dict[int, bytes] = {}
    for i in range(count):
        entry = data[6 + 16 * i:22 + 16 * i]
        if len(entry) < 16:
            break
        w, h, _colors, _reserved, _planes, _bpp, size, off = struct.unpack('<BBBBHHII', entry)
        edge = w or 256, h or 256      # 0 means 256: the field is one byte
        if edge[0] != edge[1]:
            continue
        blob = data[off:off + size]
        if blob[:4] != b'\x89PNG':
            continue
        out[edge[0]] = blob
    return out


def desktop_text() -> str:
    text = DESKTOP.read_text(encoding='utf-8')
    # sh-quoted: a folder with a space in the checkout path is ordinary on Linux.
    return text.replace('@LAUNCHER@', f'"{LAUNCHER.resolve()}"')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--uninstall', action='store_true', help='remove what this installed')
    parser.add_argument('--dry-run', action='store_true', help='print what would be written, write nothing')
    parser.add_argument('--home', type=Path, default=None, help='instead of $XDG_DATA_HOME/~/.local/share')
    parser.add_argument('--bin', type=Path, default=None, help='instead of $XDG_BIN_HOME/~/.local/bin')
    args = parser.parse_args()

    if not LAUNCHER.exists():
        raise SystemExit(f'{LAUNCHER}: missing')
    if not DESKTOP.exists():
        raise SystemExit(f'{DESKTOP}: missing')

    data = args.home or Path(os.environ.get('XDG_DATA_HOME') or (Path.home() / '.local' / 'share'))
    bindir = args.bin or Path(os.environ.get('XDG_BIN_HOME') or (Path.home() / '.local' / 'bin'))
    desk = data / 'applications' / f'{APP}.desktop'
    pngs = ico_pngs(ICO)
    icons = [data / 'icons' / 'hicolor' / f'{n}x{n}' / 'apps' / f'{APP}.png' for n in sorted(pngs)]
    link = bindir / APP

    if args.uninstall:
        for p in [desk, link, *icons]:
            if p.is_symlink() or p.exists():
                print(f'rm  {p}')
                if not args.dry_run:
                    p.unlink()
        return 0

    if not (ROOT / 'build' / 'oot111' / 'ocarina').exists():
        # Not fatal: the entry can be installed before the build, but say so rather than leave a dead icon.
        print('note: build/oot111/ocarina is not there yet, so the entry will open a launcher that reports a missing '
              'build. Run this again after the build, or ignore it if the build goes elsewhere.', file=sys.stderr)

    written: list[Path] = []
    if not args.dry_run:
        desk.parent.mkdir(parents=True, exist_ok=True)
        desk.write_text(desktop_text(), encoding='utf-8')
        desk.chmod(0o644)
    written.append(desk)

    if not pngs:
        print(f'note: {ICO} carries no PNG sizes; the entry will use a generic icon.', file=sys.stderr)
    for n, blob in sorted(pngs.items()):
        p = data / 'icons' / 'hicolor' / f'{n}x{n}' / 'apps' / f'{APP}.png'
        if not args.dry_run:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(blob)
        written.append(p)

    if not args.dry_run:
        bindir.mkdir(parents=True, exist_ok=True)
        LAUNCHER.chmod(0o755)
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(LAUNCHER.resolve())
    written.append(link)

    for p in written:
        print(f'wrote {p}')

    if not args.dry_run:
        refresh = shutil.which('update-desktop-database')
        if refresh:   # the menu picks the entry up without a session restart
            subprocess.run([refresh, str(data / 'applications')], check=False)
        apps = shutil.which('gtk-launch')
        print()
        print(f'The entry is installed. It appears in the app launcher as "{APP}"; from a shell, {bindir}/ocarina-recomp '
              f'works if {bindir} is on PATH.')
        if apps:
            print(f'Check it with: gtk-launch {APP}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
