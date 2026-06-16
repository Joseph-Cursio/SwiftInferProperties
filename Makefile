# SwiftInferProperties — test orchestration.
#
# The verify suites are `.tags(.subprocess)`: each spawns real `swift build`
# + verifier runs (the `.tca` ones resolve swift-composable-architecture +
# swift-syntax). Running all 16 at once spikes temp-disk usage and contends
# with the PRD §13 perf-budget tests, so `make test` runs the fast suite plus
# four sequential subprocess batches. See CLAUDE.md "Build & test".

SWIFT_TEST := swift test

# All 16 `.subprocess` suites match this regex: the 10 `*MeasuredTests`,
# `InteractionVerifyMeasuredExecutionTests`, and the 5 `VerifyPipeline*`.
# It deliberately EXCLUDES the fast `MeasuredPromotionDeterminismTests`
# ("Measured" is a prefix there, not the `…MeasuredTests` suffix).
SUBPROCESS_RE := MeasuredTests|MeasuredExecutionTests|VerifyPipeline

# Subprocess batches — sized to bound peak temp-disk + build contention.
BATCH1 := TCAVerifyCorpusMeasuredTests|TCACarrierMeasuredTests
BATCH2 := CardinalityVerifyCorpusMeasuredTests|BiconditionalVerifyCorpusMeasuredTests|RefIntVerifyCorpusMeasuredTests
BATCH3 := VerifyPipeline
BATCH4 := InteractionVerifyMeasuredExecutionTests|IdempotenceCorpusMeasuredTests|IdempotenceSurveyCorpusMeasuredTests|VerifyInteractionSurveyMeasuredTests|PromotionDeterminismMeasuredTests|ConservationSurveyCorpusMeasuredTests

# Never run batches concurrently (peak-disk + perf-contention safety), even
# under `make -j`.
.NOTPARALLEL:
.DEFAULT_GOAL := help
.PHONY: help test test-fast batch1 batch2 batch3 batch4 clean-temp

help: ## List targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

test: test-fast batch1 batch2 batch3 batch4 ## Fast suite + the four subprocess batches, in sequence (fail-fast)

test-fast: ## Every non-subprocess test (~6s, 3200 tests)
	$(SWIFT_TEST) --skip '$(SUBPROCESS_RE)'

batch1: ## Subprocess batch 1 — TCA carrier + verify-ready corpus (heaviest)
	$(SWIFT_TEST) --filter '$(BATCH1)'

batch2: ## Subprocess batch 2 — cardinality/biconditional/refint corpus surveys
	$(SWIFT_TEST) --filter '$(BATCH2)'

batch3: ## Subprocess batch 3 — VerifyPipeline* integration suites
	$(SWIFT_TEST) --filter '$(BATCH3)'

batch4: ## Subprocess batch 4 — interaction/idempotence/conservation/determinism
	$(SWIFT_TEST) --filter '$(BATCH4)'

clean-temp: ## Remove leftover verifier/corpus build dirs (from killed runs)
	find "$${TMPDIR:-/tmp}" -maxdepth 1 \( -name '*verify-pipeline-integration*' -o -name '*verify-interaction*' -o -name '*-corpus*' -o -name '*-survey-corpus*' -o -name 'TemporaryDirectory.*' -o -name '*.lock' \) -exec rm -rf {} + 2>/dev/null || true
	@df -h / | tail -1
