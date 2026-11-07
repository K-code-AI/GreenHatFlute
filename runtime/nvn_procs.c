// NVN proc table. Every name the game's proc loader asks for gets a synthetic host
// address through hostfn_register before hostfn_seal; nvnBootstrapLoader and nvnDeviceGetProcAddress hand them out.
// nvnp_<name> is the implementation of one proc: the weak definitions here stop with the proc's name, nvn_api_*.c
// and nvn_ext.c define the strong ones. The name list is runtime/nvn_procs.inc (tools/gen_nvn_procs.py).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gfx.h"
#include "host.h"
#include "platform/platform.h"

// The strong nvnp_nvnDeviceGetProcAddress below replaces the stand-in generated for the same row.
#define nvnp_nvnDeviceGetProcAddress nvnp_stub_nvnDeviceGetProcAddress

#define NVN_PROC(n) void nvnp_##n(Cpu *c);
#include "nvn_procs.inc"
#undef NVN_PROC

#define NVN_PROC(n)                                                                                                  \
    __attribute__((weak)) void nvnp_##n(Cpu *c) {                                                                     \
        (void)c;                                                                                                     \
        { static volatile int32_t seen; if (!__atomic_exchange_n(&seen, 1, __ATOMIC_RELAXED)) rt_log("nvn: LOCAL TEST: " #n " is not implemented, returning 0"); ret_x(c, 0); }                                                                   \
    }
#include "nvn_procs.inc"
#undef NVN_PROC
#undef nvnp_nvnDeviceGetProcAddress
void nvnp_nvnDeviceGetProcAddress(Cpu *c);

typedef struct { const char *name; uint64_t addr; } Proc;

#define NVN_PROC(n) +1
enum { PROC_COUNT = 0
#include "nvn_procs.inc"
};
#undef NVN_PROC

static Proc procs[PROC_COUNT];
static int nprocs;

static int by_name(const void *a, const void *b) { return strcmp(((const Proc *)a)->name, ((const Proc *)b)->name); }

// LOCAL TEST (Ocarina): names newer than this table get a stub that does nothing and answers 0, with the caller logged
// once each. hostfn_register stops at the seal, which the game's proc loader runs after, so the stubs are reserved as a
// pool here: every unknown name takes the next free one, and the stub recovers that name from its own synthetic address
// (hostfn_name(c->pc)), so the log says which proc the game called instead of just where.
#define MISSING_SLOTS 64
static const char missing_prefix[] = "nvn:missing";
static char missing_slot_name[MISSING_SLOTS][16];
static char missing_label[MISSING_SLOTS][96];
static uint64_t missing_slot_addr[MISSING_SLOTS];
static int nmissing;
static int missing_slot_of(const char *name) {
    for (int i = 0; i < nmissing; i++)
        if (!strcmp(missing_label[i], name)) return i;
    if (nmissing >= MISSING_SLOTS) return MISSING_SLOTS - 1;   // the last stub answers for the rest
    strncpy(missing_label[nmissing], name, sizeof missing_label[0] - 1);
    return nmissing++;
}

static void nvnp_missing_proc(Cpu *c) {
    const char *self = hostfn_name(c->pc);
    int slot = self ? atoi(self + (sizeof missing_prefix - 1)) : -1;
    const char *name = slot >= 0 && slot < MISSING_SLOTS && missing_label[slot][0] ? missing_label[slot] : NULL;
    static uint64_t seen[64];
    static int n;
    uint64_t lr = c->x[30];
    int known = 0;
    for (int i = 0; i < n; i++) known |= seen[i] == lr;
    if (!known && n < 64) {
        seen[n++] = lr;
        rt_log("nvn: LOCAL TEST: missing proc %s called from %#llx", name ? name : "(unnamed)",
               (unsigned long long)lr);
    }
    ret_x(c, 0);
}

void nvn_procs_register(void) {
    if (nprocs) return;
    for (int i = 0; i < MISSING_SLOTS; i++) {
        snprintf(missing_slot_name[i], sizeof missing_slot_name[i], "%s%d", missing_prefix, i);
        missing_slot_addr[i] = hostfn_register(missing_slot_name[i], nvnp_missing_proc);
    }
#define NVN_PROC(n) procs[nprocs++] = (Proc){#n, hostfn_register("nvn:" #n, nvnp_##n)};
#include "nvn_procs.inc"
#undef NVN_PROC
    qsort(procs, (size_t)nprocs, sizeof *procs, by_name);
}

uint64_t nvn_proc_address(const char *name) {
    if (!name) return 0;
    const Proc *p = bsearch(&(Proc){name, 0}, procs, (size_t)nprocs, sizeof *procs, by_name);
    if (p) return p->addr;
    // Unknown names get NULL, as on hardware; each distinct one is logged once.
    static PlatMutex lock = PLAT_MUTEX_INIT;
    static char seen[32][96];
    static int nseen;
    plat_mutex_lock(&lock);
    int fresh = 1;
    for (int i = 0; i < nseen; i++)
        if (!strncmp(seen[i], name, sizeof seen[i] - 1)) fresh = 0;
    if (fresh && nseen < 32) {
        strncpy(seen[nseen], name, sizeof seen[0] - 1);
        nseen++;
    } else {
        fresh = 0;
    }
    plat_mutex_unlock(&lock);
    if (fresh) rt_log("nvn: no such proc \"%s\", returning a stub", name);
    return missing_slot_addr[missing_slot_of(name)];
}

// PFNNVNGENERICFUNC nvnDeviceGetProcAddress(const NVNdevice *device, const char *name)
void nvnp_nvnDeviceGetProcAddress(Cpu *c) {
    const char *name = arg_p(c, 1);
    ret_x(c, nvn_proc_address(name));
}
