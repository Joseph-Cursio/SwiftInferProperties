# SwiftInferProperties — test orchestration.
#
# The verify suites are `.tags(.subprocess)`: each spawns real `swift build`
# + verifier runs (the `.tca` ones resolve swift-composable-architecture +
# swift-syntax). Running them all at once spikes temp-disk usage and contends
# with the PRD §13 perf-budget tests, so `make test` runs the fast suite plus
# seven sequential subprocess batches. See CLAUDE.md "Build & test".
#
# The §13 perf suites are ALSO isolated, for the same reason from the other
# side. They assert wall-clock and peak-RSS budgets, so running them next to
# ~4,300 other tests measures the MACHINE, not the code: observed 3.65s against
# a 2s budget and 1008 MB against an 800 MB one in a loaded run, with all five
# passing in 6.1s and 167 MB immediately afterwards in isolation. A budget test
# that shares a box with a full test suite is not a budget test, and its flakes
# cost more than they catch — every one has to be re-run by hand to find out it
# was noise. They now run alone, in their own serial target.

SWIFT_TEST := swift test

# Every `.subprocess` suite matches this regex: the `*MeasuredTests` family,
# `InteractionVerifyMeasuredExecutionTests`, and the 6 `VerifyPipeline*`.
# It deliberately EXCLUDES the fast `MeasuredPromotionDeterminismTests`
# ("Measured" is a prefix there, not the `…MeasuredTests` suffix).
# IMPORTANT: every suite matched here MUST appear in exactly one BATCH below
# (`make test` runs the batches, not this regex), else it's skipped-by-fast
# AND never run — the cycle-N orphaning trap. The MVVM suites (BATCH5) were
# orphaned this way until BATCH5 was added; the TCA-corpus + composition-payload
# suites (BATCH6/BATCH7) were orphaned until those batches were added.
SUBPROCESS_RE := MeasuredTests|MeasuredExecutionTests|VerifyPipeline

# The five PRD §13 budget suites, all in Tests/SwiftInferPerformanceTests/ and
# all named `*PerformanceTests` (DriftIncremental, InteractiveFirstPrompt,
# MemoryCeiling, TestLifter, and the bare `PerformanceTests`). Same contract as
# SUBPROCESS_RE: skipped by the fast path, so a suite matched here MUST be run
# by the `perf` target below or it is never run at all. A new perf suite is
# auto-covered by both only if it keeps the `*PerformanceTests` suffix.
PERF_RE := PerformanceTests

# Subprocess batches — sized to bound peak temp-disk + build contention. Note
# the batch FILTERS are substrings, so `BATCH3 := VerifyPipeline` matches every
# `VerifyPipeline*` suite. Keep every regex-matched suite in exactly one batch.
BATCH1 := TCAVerifyCorpusMeasuredTests|TCACarrierMeasuredTests|MobiusVerifyCorpusMeasuredTests
BATCH2 := CardinalityVerifyCorpusMeasuredTests|BiconditionalVerifyCorpusMeasuredTests|RefIntVerifyCorpusMeasuredTests
BATCH3 := VerifyPipeline
BATCH4 := InteractionVerifyMeasuredExecutionTests|IdempotenceCorpusMeasuredTests|IdempotenceSurveyCorpusMeasuredTests|VerifyInteractionSurveyMeasuredTests|PromotionDeterminismMeasuredTests|ConservationSurveyCorpusMeasuredTests|AlgebraicSurveyCorpusMeasuredTests
# MVVM-carrier verify suites (dependency-free builds — light; one batch is fine).
BATCH5 := ViewModelVerifyCorpusMeasuredTests|ViewModelRefintVerifyCorpusMeasuredTests|ViewModelKeyedRefintVerifyMeasuredTests|VMStateInvariantVerifyMeasuredTests|ViewModelFakedDepVerifyMeasuredTests|ViewModelPackageVerifyMeasuredTests|ViewModelVerifyEvidenceJoinMeasuredTests|ViewModelM1PrimeVerifyMeasuredTests
# Composition-action payload measured suites (slices 2/3/4 — TCA corpus builds).
BATCH6 := CompositionPayloadCorpusMeasuredTests|IdentifiedActionCorpusMeasuredTests|BindingActionCorpusMeasuredTests|TraceMiningMeasuredTests
# TCA/redux determinism / real-examples / unknown-action / multi-module corpora,
# plus the generator-recipe compile guard (a single light kit-only build).
BATCH7 := DeterminismVerifyCorpusMeasuredTests|TCADeterminismCorpusMeasuredTests|TCAExamplesMeasuredTests|UnknownActionCorpusMeasuredTests|MultiModuleVerifyMeasuredTests|GeneratorRecipeCompileMeasuredTests|AlgebraicLawsVerifyMeasuredTests|VerifyEmitterMatrixMeasuredTests|RecursiveCarrierMeasuredTests
# Codec round-trip / output-determinism / reorder / value-semantics corpora.
# These eight had NEVER run — matched by SUBPROCESS_RE (so skipped by the fast
# path) and named by no batch, from the day each was written until 2026-08-05.
# `SubprocessBatchCoverageTests` now fails if that recurs; the Makefile comment
# above asking for it was unenforced prose for nine suites' worth of drift.
# Measured when first run: 8 suites, ~206s total, all green.
BATCH8 := CodableRoundTripCorpusMeasuredTests|CodableRoundTripLiveSurveyMeasuredTests|InitDecodeCorpusMeasuredTests|OutputDeterminismCorpusMeasuredTests|OutputDeterminismJoinMeasuredTests|ReorderPartitionCorpusMeasuredTests|ValueSemanticVerifyMeasuredTests|ValueSemanticPackageVerifyMeasuredTests

# Never run batches concurrently (peak-disk + perf-contention safety), even
# under `make -j`.
.NOTPARALLEL:
.DEFAULT_GOAL := help
.PHONY: help test test-fast lint perf batch1 batch2 batch3 batch4 batch5 batch6 batch7 batch8 clean-temp

help: ## List targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

test: lint test-fast perf batch1 batch2 batch3 batch4 batch5 batch6 batch7 batch8 ## Lint + fast suite + §13 perf + the eight subprocess batches, in sequence (fail-fast)

# `lint` gates `test-fast` (the command cycle commits run) so a SwiftLint
# regression fails the same way a test failure does. `--strict` upgrades
# warnings to a non-zero exit; `--quiet` prints only violations. History: lint
# warnings repeatedly slipped through cycle commits because `swift test` doesn't
# run SwiftLint (e.g. file_length/type_body_length from added tests). Make is
# .NOTPARALLEL and dedupes shared prerequisites, so lint runs once before tests.
test-fast: lint ## SwiftLint + every non-subprocess, non-perf test (~6s)
	$(SWIFT_TEST) --skip '$(SUBPROCESS_RE)|$(PERF_RE)'

lint: ## SwiftLint, failing on any warning (--strict)
	@command -v swiftlint >/dev/null 2>&1 || { echo "Error: swiftlint not installed (brew install swiftlint)." >&2; exit 1; }
	swiftlint lint --quiet --strict

perf: ## PRD §13 wall-clock + peak-RSS budgets, alone and serial (see header)
	$(SWIFT_TEST) --filter '$(PERF_RE)' --no-parallel

batch1: ## Subprocess batch 1 — TCA carrier + verify-ready corpus (heaviest)
	$(SWIFT_TEST) --filter '$(BATCH1)'

batch2: ## Subprocess batch 2 — cardinality/biconditional/refint corpus surveys
	$(SWIFT_TEST) --filter '$(BATCH2)'

batch3: ## Subprocess batch 3 — VerifyPipeline* integration suites
	$(SWIFT_TEST) --filter '$(BATCH3)'

batch4: ## Subprocess batch 4 — interaction/idempotence/conservation/determinism
	$(SWIFT_TEST) --filter '$(BATCH4)'

batch5: ## Subprocess batch 5 — MVVM-carrier verify suites (ViewModel/VMState)
	$(SWIFT_TEST) --filter '$(BATCH5)'

batch6: ## Subprocess batch 6 — composition-action payload measured (slices 2/3/4)
	$(SWIFT_TEST) --filter '$(BATCH6)'

batch7: ## Subprocess batch 7 — TCA determinism / real-examples / unknown-action
	$(SWIFT_TEST) --filter '$(BATCH7)'

batch8: ## Subprocess batch 8 — codec round-trip / output-determinism / value-semantics
	$(SWIFT_TEST) --filter '$(BATCH8)'

docs-drift: ## Report which docs/design-internal/ docs have a subject repo that has moved
	@./scripts/docs_drift.sh

clean-temp: ## Remove leftover verifier/corpus/measured build dirs (from killed runs + verify surveys)
	find "$${TMPDIR:-/tmp}" -maxdepth 1 \( -name '*verify-pipeline-integration*' -o -name '*verify-interaction*' -o -name '*-corpus*' -o -name '*-survey-corpus*' -o -name '*measured*' -o -name 'tca-*' -o -name 'vm-*' -o -name 'TemporaryDirectory.*' -o -name '*.lock' \) -exec rm -rf {} + 2>/dev/null || true
# `verify --all-from-index` does NOT use $TMPDIR — it synthesizes one workdir per
# suggestion under <packageRoot>/.swiftinfer/verify-workdir/, each with its own
# .build/. A survey of the repo's own 85-entry index left 3.4 GB there. Gitignored,
# so `git status` shows nothing but the directory name and it accumulates silently.
	rm -rf .swiftinfer/verify-workdir
	@df -h "$${TMPDIR:-/tmp}" | tail -1
