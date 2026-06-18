# SwiftInferProperties — test orchestration.
#
# The verify suites are `.tags(.subprocess)`: each spawns real `swift build`
# + verifier runs (the `.tca` ones resolve swift-composable-architecture +
# swift-syntax). Running all 16 at once spikes temp-disk usage and contends
# with the PRD §13 perf-budget tests, so `make test` runs the fast suite plus
# four sequential subprocess batches. See CLAUDE.md "Build & test".

SWIFT_TEST := swift test

# All 23 `.subprocess` suites match this regex: the `*MeasuredTests` family,
# `InteractionVerifyMeasuredExecutionTests`, and the 5 `VerifyPipeline*`.
# It deliberately EXCLUDES the fast `MeasuredPromotionDeterminismTests`
# ("Measured" is a prefix there, not the `…MeasuredTests` suffix).
# IMPORTANT: every suite matched here MUST appear in exactly one BATCH below
# (`make test` runs the batches, not this regex), else it's skipped-by-fast
# AND never run — the cycle-N orphaning trap. The 7 MVVM suites (BATCH5) were
# orphaned this way until they were wired in.
SUBPROCESS_RE := MeasuredTests|MeasuredExecutionTests|VerifyPipeline

# Subprocess batches — sized to bound peak temp-disk + build contention.
BATCH1 := TCAVerifyCorpusMeasuredTests|TCACarrierMeasuredTests|MobiusVerifyCorpusMeasuredTests
BATCH2 := CardinalityVerifyCorpusMeasuredTests|BiconditionalVerifyCorpusMeasuredTests|RefIntVerifyCorpusMeasuredTests
BATCH3 := VerifyPipeline
BATCH4 := InteractionVerifyMeasuredExecutionTests|IdempotenceCorpusMeasuredTests|IdempotenceSurveyCorpusMeasuredTests|VerifyInteractionSurveyMeasuredTests|PromotionDeterminismMeasuredTests|ConservationSurveyCorpusMeasuredTests|AlgebraicSurveyCorpusMeasuredTests
# MVVM-carrier verify suites (dependency-free builds — light; one batch is fine).
BATCH5 := ViewModelVerifyCorpusMeasuredTests|ViewModelRefintVerifyCorpusMeasuredTests|ViewModelKeyedRefintVerifyMeasuredTests|VMStateInvariantVerifyMeasuredTests|ViewModelFakedDepVerifyMeasuredTests|ViewModelPackageVerifyMeasuredTests|ViewModelVerifyEvidenceJoinMeasuredTests

# Never run batches concurrently (peak-disk + perf-contention safety), even
# under `make -j`.
.NOTPARALLEL:
.DEFAULT_GOAL := help
.PHONY: help test test-fast lint batch1 batch2 batch3 batch4 batch5 clean-temp

help: ## List targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

test: lint test-fast batch1 batch2 batch3 batch4 batch5 ## Lint + fast suite + the five subprocess batches, in sequence (fail-fast)

# `lint` gates `test-fast` (the command cycle commits run) so a SwiftLint
# regression fails the same way a test failure does. `--strict` upgrades
# warnings to a non-zero exit; `--quiet` prints only violations. History: lint
# warnings repeatedly slipped through cycle commits because `swift test` doesn't
# run SwiftLint (e.g. file_length/type_body_length from added tests). Make is
# .NOTPARALLEL and dedupes shared prerequisites, so lint runs once before tests.
test-fast: lint ## SwiftLint + every non-subprocess test (~6s, 3200 tests)
	$(SWIFT_TEST) --skip '$(SUBPROCESS_RE)'

lint: ## SwiftLint, failing on any warning (--strict)
	@command -v swiftlint >/dev/null 2>&1 || { echo "Error: swiftlint not installed (brew install swiftlint)." >&2; exit 1; }
	swiftlint lint --quiet --strict

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

clean-temp: ## Remove leftover verifier/corpus/measured build dirs (from killed runs)
	find "$${TMPDIR:-/tmp}" -maxdepth 1 \( -name '*verify-pipeline-integration*' -o -name '*verify-interaction*' -o -name '*-corpus*' -o -name '*-survey-corpus*' -o -name '*measured*' -o -name 'tca-*' -o -name 'vm-*' -o -name 'TemporaryDirectory.*' -o -name '*.lock' \) -exec rm -rf {} + 2>/dev/null || true
	@df -h "$${TMPDIR:-/tmp}" | tail -1
