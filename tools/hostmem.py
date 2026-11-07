"""Memory the machine can still give to new processes, for sizing worker pools (stdlib only)."""
import pathlib

MEMINFO = pathlib.Path('/proc/meminfo')
CGROUP_MAX = pathlib.Path('/sys/fs/cgroup/memory.max')
CGROUP_CURRENT = pathlib.Path('/sys/fs/cgroup/memory.current')


def _mem_available():
    """MemAvailable in bytes: what new processes can get before the machine starts swapping. None without /proc."""
    try:
        for line in MEMINFO.read_text().splitlines():
            key, _, rest = line.partition(':')
            if key.strip() != 'MemAvailable':
                continue
            fields = rest.split()
            if fields and fields[-1] == 'kB':
                return int(fields[0]) * 1024
    except (OSError, ValueError):
        return None
    return None


def _cgroup_headroom():
    """Bytes left under the memory limit of the cgroup this process runs in, or None without such a limit."""
    try:
        limit = CGROUP_MAX.read_text().strip()
        if limit == 'max':
            return None
        limit, used = int(limit), int(CGROUP_CURRENT.read_text().strip())
    except (OSError, ValueError):
        return None
    return max(0, limit - used)


def available_ram():
    """Physical memory not in use right now, capped by the cgroup limit if there is one. None when unknown."""
    available = _mem_available()
    if available is None:
        return None
    headroom = _cgroup_headroom()
    return available if headroom is None else min(available, headroom)
