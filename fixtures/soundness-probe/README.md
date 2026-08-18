# Soundness-arm probe fixture

A deliberately tiny package for phase 0.5's probe. **Not a corpus** — its only job is to
give the nine trip-list subjects something real to read, so that denying reads of this
directory produces an observable difference.

Pointing the probe at the repository root instead was tried first and hung: the scanners
walk `.build`, which is gigabytes. A fixture bounds the run.
