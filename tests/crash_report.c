// A fault outside this executable, and one inside it, with the platform layer's crash hook not installed. No game,
// window or GPU.
//
// A crash in a driver or in the C runtime's heap is not our code, so main.c's report (which names
// GreenHatFlute+<offset>) cannot be used for it; the process used to end with no word in the log. platform/linux.c
// now writes one line naming the module, the offset, the thread and what that thread said it was working on
// (plat_crash_note), plus the memory numbers. This fixture takes the fault on purpose so the line can be checked.
//
//   crash_report libc   strlen(NULL): the fault lands in libc
//   crash_report self   a null store of our own: the fault lands in this executable
#include <stdio.h>
#include <string.h>

#include "platform/platform.h"

// platform/linux.c reaches for the clipboard; this test does not link SDL (as tests/fiber_stack.c does).
int SDL_SetClipboardText(const char *text) { (void)text; return -1; }

int main(int argc, char **argv) {
    int in_libc = argc > 1 && !strcmp(argv[1], "libc");
    plat_crash_hook(NULL);   // no report of our own: the platform line is all the run leaves
    if (in_libc) {
        plat_crash_note("fixture: strlen of a null pointer, inside libc");
        const char *volatile p = NULL;
        size_t n = strlen((const char *)p);
        printf("FAIL: the fault was not taken (%zu)\n", n);
    } else {
        plat_crash_note("fixture: a null store in this executable");
        int *volatile p = NULL;
        *p = 7;
        printf("FAIL: the fault was not taken (%d)\n", *p);
    }
    return 1;
}
