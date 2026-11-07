#!/bin/sh
# Builds Instalar-Ocarina.exe in this folder. Run in the MSYS2 UCRT64 shell, or with C:\msys64\ucrt64\bin on PATH.
set -e
cd "$(dirname "$0")"
windres launcher.rc -O coff -o launcher.res
clang -O2 -mwindows launcher.c launcher.res -static -o Instalar-Ocarina.exe
rm -f launcher.res
sha256sum Instalar-Ocarina.exe
