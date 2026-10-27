# Swift Testing output captures (#665)

These are real `swift test` outputs, replayed by `python3 scripts/corpus_funnel_stage5.py --self-test`
(part of `make measurement-selftest`) through `parse_test_output`. Each capture is checked against
`expected.json`, which has two halves:

- **`started` and `results`** come from the **unpatched** parse loop, cut verbatim out of
  `run_serially` in `fef2971d:scripts/corpus_funnel_stage5.py` (from `suite, started = None, []`
  through the `_FAILED` branch). The loop was dedented and `exec`'d in that module's own globals,
  so its regexes are fef2971d's too, with `output` set to the capture and `results` to `{}`. The
  patch must reproduce them exactly. This is what keeps arm A's law columns comparable with every
  census before #665.
- **`warned` and `sides`** were read off the captures by hand, not computed by the patched parser.
  They list the tests whose line reads `recorded a warning` or `recorded a known issue`, and the
  side each `↳ NOT APPLIED — the <true|false> side:` line names for the issue directly above it.

Each capture is a run's stdout followed by its stderr, which is how `run_serially` reads it. The
toolchains are swift.org 6.4.1 (`swiftorg`) and Xcode 27's `swiftlang-6.4.0.34.1` (`xcode`), both
run with `NO_COLOR=1`. Absolute paths are replaced by `<package>` and `<swift.org-6.4.1-toolchain>`.

| Capture | What it is |
|---|---|
| `severity-out-<tc>.stdout`, `severity-out-<tc>.stderr`, `severity-all-<tc>.txt` | The severity toy's four tests in one run: (a) `Issue.record`, an error; (b) `severity: .warning`; (c) `withKnownIssue { Issue.record }`; (d) a clean pass. `all` is `out`'s stdout followed by its stderr. Each message reads `NOT APPLIED — a`, so no side is named. |
| `severity-only-<tc>-{aErrorIssue,bWarningIssue,cKnownIssue}.out` | The same tests, each run alone (`--filter`). |
| `severity-filt-<tc>-eKnownIssueNotRecorded.out` | (e) `withKnownIssue` whose body records nothing, so the test fails with *Known issue was not recorded*. The test's comment prints as a `↳` line AFTER the `failed` line, so it is nobody's detail. |
| `severity-filt-<tc>-fKnownIssueIntermittentNotRecorded.out` | (f) The same, but `isIntermittent: true`, so it passes clean. |
| `helper-<tc>.out` | The W form through its per-stub `reachNote` helper. Two test targets, one with `defaultIsolation(MainActor)`, each with a suite declaring `isEven_reachesBothOutcomes()`, so one test name appears under two suites. |
| `reach-mixed.txt` | Nine predicate suites' reach tests in one run: seven green, `isMagic` FAILS naming the true side (E), and `isRepresentable` passes with a warning naming the false side (W). The toolchain was not recorded with this run. |
| `known-issue-side.out` | The known-issue form (the W fallback before Swift 6.3) carrying a side, after a passing `_isTotal` law (swift.org 6.4.1). |
| `trap.out` | A law and its reach twin pass, then `isOdd_isTotal()` traps (index out of range) before its twin can start, so `started` holds one test with no result. Taken with `--skip` over the hanging suite (swift.org 6.4.1). |
| `hang-quiet.out` | A law that spins with almost nothing printed, killed at 15 s. Only SwiftPM's own build lines arrive: no test output reaches the pipe, not even `started` (N1). This is stage 5's `no_verdict` path. |
| `hang-big-truncated.out` | N10's large-output hang: 20,000 stderr and 20,000 `print` lines of about 50 bytes each, then a spin, killed at 20 s. 39,913 lines arrived, including the `started` line, and the relay's tail was cut mid-line. Only the first 200 and last 200 lines are kept. |

The trap, quiet-hang, known-issue and large-hang captures were taken through stage 5's own call:
`subprocess.run([swift, "test", "--no-parallel", …], capture_output=True, text=True, timeout=T)`.
On a timeout the output is the partial `TimeoutExpired.stdout` and `.stderr`. Afterwards, every
process whose command contained the package's real `.build` path was killed with `kill -9`.

To re-create the expected file after an intended parser change, regenerate the `started` and
`results` halves from the fef2971d loop in the same way, and never from the patched parser.
