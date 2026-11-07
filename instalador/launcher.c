// Instalar-Ocarina.exe: writes the installer script it carries (Instalar-Ocarina.ps1, the same file as in this folder) to a
// temporary file, runs it with PowerShell and deletes it. It does nothing else. Build with instalador/build_exe.sh.
#include <windows.h>

int WINAPI WinMain(HINSTANCE self, HINSTANCE prev, LPSTR line, int show) {
    (void)prev, (void)line, (void)show;
    HRSRC res = FindResourceW(self, MAKEINTRESOURCEW(101), MAKEINTRESOURCEW(10));   // 10: RT_RCDATA
    HGLOBAL data = res ? LoadResource(self, res) : NULL;
    if (!data) return 2;
    wchar_t dir[MAX_PATH], path[MAX_PATH], cmd[2 * MAX_PATH + 128];
    GetTempPathW(MAX_PATH, dir);
    if (!GetTempFileNameW(dir, L"oot", 0, path)) return 3;
    DeleteFileW(path);
    lstrcatW(path, L".ps1");
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD wrote = 0, size = SizeofResource(self, res);
    if (f == INVALID_HANDLE_VALUE) return 4;
    WriteFile(f, LockResource(data), size, &wrote, NULL);
    CloseHandle(f);
    if (wrote != size) { DeleteFileW(path); return 5; }
    wchar_t sys[MAX_PATH];   // by full path: a PATH that is too long or broken must not hide it
    GetSystemDirectoryW(sys, MAX_PATH);
    wsprintfW(cmd, L"\"%s\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%s\"", sys, path);
    STARTUPINFOW si = {.cb = sizeof si};
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        DeleteFileW(path);
        MessageBoxW(NULL, L"PowerShell not found.", L"Ocarina Recomp", MB_ICONERROR);
        return 6;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DeleteFileW(path);
    return 0;
}
