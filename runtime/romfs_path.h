// From MacNativeGames games/totk/runtime/romfs_path.h @ b75be8cf (MIT, Copyright (c) 2026 MacNativeGames
// contributors).
// RomFS path validation shared by the runtime (romfs.c) and its probe (fs_host.c probe_fs).
#pragma once
#include <stddef.h>
#include <string.h>

// A RomFS-relative path: non-empty, no leading '/', no '\', no empty, "." or ".." component.
static inline int romfs_path_valid_relative(const char *path) {
    if (!path || !*path || *path == '/' || strchr(path, '\\')) return 0;
    for (const char *part = path; *part;) {
        const char *end = strchr(part, '/');
        size_t size = end ? (size_t)(end - part) : strlen(part);
        if (!size || (size == 1 && part[0] == '.') || (size == 2 && part[0] == '.' && part[1] == '.')) return 0;
        if (!end) break;
        part = end + 1;
    }
    return 1;
}

// "<mount>:/<path>" -> "<path>", or NULL. The game joins a mount root and a leading-slash resource, and the join
// leaves a repeated separator: "content://Sound/Resource/Stream/x.bwav" for music, and one inside the path for
// speech ("content://Voice/Resource//Stream/x.bwav", 7726 of the game's files). Repeated separators collapse to one
// and a trailing one is dropped; traversal, backslashes and "." components are still rejected. Collapsing only ever
// shortens the path, so the result is built in a per-thread buffer that holds it until this thread calls again:
// use it before the next call. A path longer than the buffer is refused rather than truncated.
static inline const char *romfs_path_relative(const char *mount, const char *path) {
    if (!mount || !*mount || !path) return NULL;
    size_t size = strlen(mount);
    if (strncmp(path, mount, size) || path[size] != ':' || path[size + 1] != '/') return NULL;
    path += size + 2;
    while (*path == '/') ++path;   // the join at the root: "content://Sound/..."
    if (strstr(path, "//")) {     // the join inside the path: "...Resource//Stream/..."
        static _Thread_local char kept[4096];
        size_t n = 0;
        for (const char *q = path; *q; q++) {
            if (*q == '/' && (q[1] == '/' || !q[1])) continue;   // a repeated separator, or a trailing one
            if (n + 1 >= sizeof kept) return NULL;
            kept[n++] = *q;
        }
        kept[n] = 0;
        path = kept;
    }
    return romfs_path_valid_relative(path) ? path : NULL;
}
