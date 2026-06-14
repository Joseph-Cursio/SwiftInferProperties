## Interaction-invariant acceptance rates

Sources: /Users/joecursio/xcode_projects/SwiftInferProperties/Tests/Fixtures/v2.0-corpus/.swiftinfer/interaction-decisions.json, /Users/joecursio/xcode_projects/calibration-corpora/tca-25-discovery/.swiftinfer/interaction-decisions.json, /Users/joecursio/xcode_projects/calibration-corpora/tca-10-discovery/.swiftinfer/interaction-decisions.json

| Family | Accepted | AsConformance | Rejected | Skipped | Acceptance rate | Skip rate |
|---|---:|---:|---:|---:|---:|---:|
| Idempotence | 30 | 9 | 0 | 0 | 100% | 0% |
| Biconditional | 2 | 0 | 4 | 0 | 33% | 0% |
| Cardinality | 0 | 1 | 1 | 2 | 50% | 50%* |
| Referential Integrity | 0 | 1 | 0 | 0 | 100% | 0% |
| Conservation | 0 | 1 | 0 | 0 | 100% | 0% |
| **Overall** | **32** | **12** | **5** | **2** | **90%** | **4%** |

_`*` marks families whose skip rate exceeds 30%, the rubric's refinement threshold._

