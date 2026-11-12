#!/usr/bin/env python3
"""A watchdog that kills any test process of a measurement run that grows past a memory limit.

⚠ **A generated law that allocates without bound took the whole machine down** (2026-11-12, #684's
A0 arm). `swiftpm-testing-helper` processes running the funnel's stubs reached 35 GB at 09:34 and
212 GB across five processes at 09:47. macOS ran out of swap, killed system services ("low-swap"
in its jetsam report) and rebooted at 09:50, wiping the run's logs. A test that only loops is
bounded by the funnel's timeout; one that loops and allocates exhausts memory first. And a
timed-out `swift test` used to leave its helper running (`corpus_funnel_stage5.kill_package_processes`).

The guard polls `ps` every `interval` seconds and SIGKILLs a `swiftpm-testing-helper` or `xctest`
whose command line names one of its roots (a run's `trees/` directory, as given and resolved) once
its resident size passes the limit. Only this run's processes: a `swift test` elsewhere on the
machine is never touched, which is the lesson of `corpus_funnel.census_helpers`.

**A kill is a measurement event, never silent.** Each one is appended to the guard's log as a JSON
line and kept for `drain()`, so the funnel records it on the repository's result. The killed process
reads to its parent as a crash, so the test running at the time is set aside as `crashed` — a real
outcome for a law that cannot finish, and the log says which kind of crash it was.

The limit is `MEASUREMENT_HELPER_RSS_GB` gigabytes, 8 by default. A generated law runs in about
150 MB (`MemoryCeilingPerformanceTests` budgets this repository's own suite at 800 MB).

    memory_guard.py --self-test
"""

import json
import os
import signal
import subprocess
import sys
import threading
import time

DEFAULT_LIMIT_GB = 8
TEST_PROCESSES = ("swiftpm-testing-helper", "xctest")


def limit_kb_from_environment(environ=None):
    environ = os.environ if environ is None else environ
    gigabytes = float(environ.get("MEASUREMENT_HELPER_RSS_GB") or DEFAULT_LIMIT_GB)
    return int(gigabytes * 1024 * 1024)


def root_spellings(roots):
    """Each root as given and resolved, ending in a separator: `/tmp` is `/private/tmp`, and a
    process may name either."""
    spellings = set()
    for root in roots:
        for path in (os.path.abspath(root), os.path.realpath(root)):
            spellings.add(path.rstrip(os.sep) + os.sep)
    return sorted(spellings)


def over_limit(listing, roots, limit_kb):
    """`(pid, rss_kb, command)` for each test process in a `ps -axo pid=,rss=,command=` listing that names
    one of `roots` and holds more than `limit_kb` resident."""
    spellings = root_spellings(roots)
    found = []
    for line in listing.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        pid, rss, command = int(parts[0]), int(parts[1]), parts[2]
        executable = command.split(None, 1)[0]
        if not any(name in os.path.basename(executable) for name in TEST_PROCESSES):
            continue
        if rss > limit_kb and any(spelling in command for spelling in spellings):
            found.append((pid, rss, command))
    return found


def process_listing():
    """`ps` through `Popen`, not `subprocess.run`, which the funnel's self-tests script."""
    with subprocess.Popen(["ps", "-axo", "pid=,rss=,command="], stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, text=True) as ps:
        output, _ = ps.communicate()
    return output


def kill(pid):
    try:
        os.kill(pid, signal.SIGKILL)
        return True
    except (ProcessLookupError, PermissionError):
        return False


class MemoryGuard:
    """Use as a context manager around a run: `with MemoryGuard([trees], log) as guard: …`."""

    def __init__(self, roots, log_path=None, limit_kb=None, interval=2.0, listing=process_listing,
                 killer=kill):
        self.roots = list(roots)
        self.log_path = log_path
        self.limit_kb = limit_kb_from_environment() if limit_kb is None else limit_kb
        self.interval = interval
        self.listing = listing
        self.killer = killer
        self._kills = []
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = None

    def poll(self):
        """One pass: kill every process over the limit, and return what was killed."""
        killed = []
        for pid, rss, command in over_limit(self.listing(), self.roots, self.limit_kb):
            if not self.killer(pid):
                continue
            event = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "pid": pid,
                     "rss_gb": round(rss / 1024 / 1024, 2), "limit_gb": round(self.limit_kb / 1024 / 1024, 2),
                     "command": command[:400]}
            killed.append(event)
            print(f"memory guard: killed {pid} at {event['rss_gb']} GB: {command[:160]}", file=sys.stderr,
                  flush=True)
            if self.log_path:
                with open(self.log_path, "a", encoding="utf-8") as log:
                    log.write(json.dumps(event, sort_keys=True) + "\n")
        with self._lock:
            self._kills.extend(killed)
        return killed

    def drain(self):
        """Every kill since the last drain."""
        with self._lock:
            kills, self._kills = self._kills, []
        return kills

    def _loop(self):
        while not self._stop.wait(self.interval):
            try:
                self.poll()
            except Exception as error:  # noqa: BLE001 - the guard must outlive one bad `ps`
                print(f"memory guard: poll failed: {error}", file=sys.stderr, flush=True)

    def __enter__(self):
        self._thread = threading.Thread(target=self._loop, name="memory-guard", daemon=True)
        self._thread.start()
        return self

    def __exit__(self, *_exc):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=self.interval + 5)
        return False


def self_test():
    failures = []

    def check(name, condition, detail=""):
        if not condition:
            failures.append(f"{name}: {detail}")

    root = "/private/tmp/census/trees"
    listing = "\n".join([
        f" 101 9000000 /Applications/Xcode.app/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path {root}/A/.build/x",
        f" 102 9000000 /usr/bin/xctest {root}/B/.build/y.xctest",
        f" 103 9000000 /x/swiftpm-testing-helper --test-bundle-path /Users/me/other/.build/z",
        f" 104 100000 /x/swiftpm-testing-helper --test-bundle-path {root}/C/.build/w",
        f" 105 9000000 /usr/bin/vim {root}/A/notes.txt",
        "garbage line",
    ])
    hits = over_limit(listing, ["/private/tmp/census/trees"], 8 * 1024 * 1024)
    check("over_limit picks this run's large test processes only", [h[0] for h in hits] == [101, 102],
          str(hits))
    check("a root's other spelling still matches",
          root_spellings(["/tmp"]) == sorted({"/tmp/", os.path.realpath("/tmp") + "/"}), root_spellings(["/tmp"]))
    check("the limit reads gigabytes", limit_kb_from_environment({"MEASUREMENT_HELPER_RSS_GB": "0.5"}) == 524288)
    check("the default limit is 8 GB", limit_kb_from_environment({}) == 8 * 1024 * 1024)

    killed = []
    guard = MemoryGuard([root], limit_kb=8 * 1024 * 1024, listing=lambda: listing,
                        killer=lambda pid: killed.append(pid) or pid != 102)
    events = guard.poll()
    check("poll kills what is over the limit", killed == [101, 102], str(killed))
    check("a kill that fails is not recorded", [e["pid"] for e in events] == [101], str(events))
    check("drain returns the kills once", [e["pid"] for e in guard.drain()] == [101] and guard.drain() == [])

    # The live path: a real process whose command line reads as a helper under a real root, killed by a
    # running guard. `exec -a` names it; a COPY of `/bin/sleep` would not do, since macOS kills a copied
    # platform binary at launch, which reads exactly like the guard's kill.
    import tempfile
    with tempfile.TemporaryDirectory() as scratch:
        trees = os.path.join(scratch, "trees")
        os.makedirs(trees)
        name = os.path.join(trees, "Pkg", ".build", "swiftpm-testing-helper")
        process = subprocess.Popen(["/bin/bash", "-c", f'exec -a "{name}" /bin/sleep 30'])
        time.sleep(0.3)
        seen = over_limit(process_listing(), [trees], 0)
        check("the live process is visible to the guard", any(pid == process.pid for pid, _, _ in seen), str(seen))
        log = os.path.join(scratch, "guard.jsonl")
        with MemoryGuard([trees], log_path=log, limit_kb=0, interval=0.2) as live:
            deadline = time.monotonic() + 10
            while process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
        check("a running guard kills a live process over the limit", process.poll() == -signal.SIGKILL,
              str(process.poll()))
        if process.poll() is None:
            process.kill()
        check("the kill is logged", os.path.exists(log) and f'"pid": {process.pid}' in open(log).read())
        check("the kill is kept for drain", any(e["pid"] == process.pid for e in live.drain()))

    for failure in failures:
        print("FAIL", failure)
    if failures:
        return 1
    print("memory_guard.py self-test OK  (selection by name, root and size; limit; poll and drain; a live kill)")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:2] == ["--self-test"] else (print(__doc__) or 2))
