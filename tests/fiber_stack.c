// plat_stack_base() and the host setjmp/longjmp mechanism, on Linux fibers: no game, no window, no GPU.
//
// runtime/ov_system.c answers the guest's setjmp/longjmp by copying the host stack above the setjmp, so longjmp can
// put those bytes back and return from setjmp a second time through the same frames. The guest's decoders and parsers
// leave that way on bad input, so it is ordinary flow, not an error path. Two things have to hold, and both come from
// the platform layer:
//   - plat_stack_base() names the stack the caller is really on, and changes when the thread switches fiber. That is
//     what makes "longjmp to a setjmp taken on another fiber" a fatal rather than memory corruption.
//   - __builtin_setjmp/__builtin_longjmp survive a fiber's stack, whose bytes live in our own mmap rather than a
//     thread's, and the stack copy really restores what was scribbled over.
// Both are easy to break silently, and the failure is memory corruption rather than a message: a wrong stack base lets
// "longjmp to a setjmp taken on another fiber" write over a live stack. This fixture runs the mechanism over a real
// fiber switch, on stacks the platform layer mmap'd itself, and fails when either half stops holding.
//
// host_setjmp/host_longjmp below follow ov_setjmp/jmp_back/ov_longjmp step for step, including the alloca that moves
// longjmp's own frame clear of the region being restored: without it the copy lands on the live frame and faults.

#ifdef __linux__
#define _GNU_SOURCE
#endif
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __linux__
#include <ucontext.h>
#endif

#include "platform/platform.h"

// platform/linux.c reaches for the clipboard; this test does not link SDL.
int SDL_SetClipboardText(const char *text) { (void)text; return -1; }

static int fails;

static void check(int ok, const char *what) {
    printf("%s: %s\n", ok ? "ok" : "FAIL", what);
    if (!ok) fails++;
}

#ifdef __linux__
// A fault here means the mechanism broke, not that a check failed: say so, and give an address to addr2line.
static void onsig(int sig, siginfo_t *si, void *uc) {
    (void)sig;
    unsigned long rip = ((ucontext_t *)uc)->uc_mcontext.gregs[REG_RIP];
    char msg[128];
    int n = snprintf(msg, sizeof msg, "\nFAULT rip=%#lx addr=%p\n", rip, si->si_addr);
    ssize_t w = write(2, msg, (size_t)n);
    (void)w;
    _exit(3);
}
#endif

// Noinline so the compiler cannot fold the writes away: the point is that bytes on the stack change and come back.
__attribute__((noinline)) static void scribble(char *p, size_t n, int value) { memset(p, value, n); }
__attribute__((noinline)) static int all_is(const char *p, size_t n, int value) {
    for (size_t i = 0; i < n; i++)
        if ((unsigned char)p[i] != (unsigned char)value) return 0;
    return 1;
}

// ---- the mechanism of runtime/ov_system.c, in the shape it uses -------------------------------------------
enum { JMP_STACK = 64 * 1024 };
static void *jmp_env[5];   // __builtin_setjmp
static char *jmp_sp, *jmp_copy;
static size_t jmp_n;

__attribute__((noinline)) static int host_setjmp(void) {
    if (__builtin_setjmp(jmp_env)) return 1;   // the second time, from host_longjmp
    char *sp;
    __asm__ volatile("movq %%rsp, %0" : "=r"(sp));
    char *base = (char *)plat_stack_base();
    jmp_sp = sp;
    jmp_n = (size_t)(base - sp) < JMP_STACK ? (size_t)(base - sp) : JMP_STACK;
    if (!jmp_copy) jmp_copy = malloc(JMP_STACK);
    memcpy(jmp_copy, sp, jmp_n);
    return 0;
}

__attribute__((noinline)) static void host_longjmp(void) {
    // ov_longjmp: the copy goes back above this frame, so step past it when longjmp is called close to setjmp.
    char *sp;
    __asm__ volatile("movq %%rsp, %0" : "=r"(sp));
    if (sp < jmp_sp + jmp_n + 0x1000 && sp > jmp_sp - 0x4000) {
        volatile char *room = __builtin_alloca((size_t)(sp - jmp_sp) + 0x8000);
        room[0] = 0;
    }
    memcpy(jmp_sp, jmp_copy, jmp_n);
    __builtin_longjmp(jmp_env, 1);
}

// ---- the fibers we measure on ------------------------------------------------------------------------------
static PlatFiber *f1, *f2;
static void *main_base, *base_f1, *base_f1_again, *base_f2;
static int marker_kept, marker_broken, round_trip;
static void report(void);

static void fiber_fn(void *arg) {
    char marker[512];
    int which = (int)(intptr_t)arg;
    void *base = plat_stack_base();
    char frame_below;   // sits below the base: a stack grows down, so base must be above it

    if (which == 1) {
        base_f1 = base;
        check(base && (char *)base > &frame_below, "a fiber's stack base sits above its current frame");

        // The stack-copy round trip, on this fiber's stack.
        scribble(marker, sizeof marker, 0x5a);       // the pattern the copy is supposed to bring back
        if (host_setjmp() == 0) {
            scribble(marker, sizeof marker, 0xa5);   // corrupt the region the copy holds
            marker_broken = !all_is(marker, sizeof marker, 0x5a);
            host_longjmp();                          // does not return here
            check(0, "host_longjmp returned");
        }
        round_trip = 1;
        marker_kept = all_is(marker, sizeof marker, 0x5a);

        plat_fiber_switch(f2);
        // Back on f1: the same stack, so the same base. This identity is what the cross-fiber guard relies on.
        base_f1_again = plat_stack_base();
        report();
        _exit(fails ? 1 : 0);
    }

    base_f2 = base;
    plat_fiber_switch(f1);
    for (;;) plat_yield();
}

// The fiber-side checks, run once every base has been measured.
static void report(void) {
    check(base_f1 && base_f2 && base_f1 != base_f2, "two fibers have different stack bases");
    check(base_f1 == base_f1_again, "a fiber keeps its stack base across a switch away and back");
    check(base_f1 != main_base, "a fiber's base differs from the thread's own");
    check(round_trip, "longjmp came back through setjmp");
    check(marker_broken, "the scribble really changed the stack bytes");
    check(marker_kept, "longjmp puts the host stack bytes back");
}

int main(void) {
    char frame;
#ifdef __linux__
    struct sigaction sa = {0};
    sa.sa_sigaction = onsig;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
#endif
    setvbuf(stdout, NULL, _IONBF, 0);   // the fiber leaves through _exit, which never flushes
    main_base = plat_stack_base();
    check(main_base != NULL, "plat_stack_base answers on a thread's own context");
    check(plat_stack_base() == main_base, "it is stable across calls on one thread");
    check((char *)main_base > &frame, "the thread's stack base sits above its current frame");
    check((char *)main_base - &frame < 64u * 1024u * 1024u, "the thread's stack base is near the frame, not another mapping");

    f1 = plat_fiber_new(1u << 20, fiber_fn, (void *)(intptr_t)1);
    f2 = plat_fiber_new(1u << 20, fiber_fn, (void *)(intptr_t)2);
    if (!f1 || !f2) {
        printf("FAIL: plat_fiber_new failed\n");
        return 1;
    }
    plat_fiber_self();   // the API wants this once before a thread's first switch
    plat_fiber_switch(f1);

    // Not reached: fiber_fn exits the process once it has measured everything.
    printf("FAIL: the fiber never ran\n");
    return 1;
}
