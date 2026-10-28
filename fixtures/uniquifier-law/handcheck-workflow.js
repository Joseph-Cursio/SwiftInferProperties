export const meta = {
  name: 'hand-check-669-body-disagrees',
  description: 'Hand-check each #669 body_disagrees row at its census revision, and re-read the other decision groups unscored',
  phases: [
    { title: 'Body disagrees', detail: 'one agent per flagged row: trace the witness, the contract, reachability, upstream HEAD' },
    { title: 'Decision re-read', detail: 'two agents re-read the remaining decision groups, unscored' },
  ],
}

// docs/plans/uniquifier-law-census-scope.md §8: every row flagged *body disagrees* is hand-checked before it is
// listed for upstream filing. args: { scratch, bd, recheck }. `bd` holds the flagged rows, each with its
// repository's checkout, census revision, path, line, name, owner and the joined verdict, flags and witness; `recheck`
// holds the other EXPRESSIBLE decision rows in two groups, re-read unscored beside the frozen verdicts. As run,
// `scratch` named a directory in the session's scratch directory, so set it to your own.
const RULES = `Rules:
- Read source only with \`git -C <root> show <revision>:<path>\` (and \`git -C <root> grep <pattern> <revision> -- <paths>\`), so you read the census revision, not whatever the checkout holds now.
- Never build, test, edit, fetch, checkout, stash or reset inside any of those repository checkouts. Never write anywhere except your own scratch directory, given below.
- If an executable reproduction is cheap, export the package with \`git -C <root> archive <revision> | tar -x -C <your scratch dir>/src\` and build there with plain \`swift build\` / \`swift test\`; give up on execution if the build would take more than about 6 minutes, and say so. A reproduction by reading a traced call sequence line by line is acceptable when you say that is what it is.
- Upstream reads are allowed only read-only, with \`gh api\` (for example \`gh api repos/OWNER/REPO/contents/PATH\` for the default branch, and \`gh search issues --repo OWNER/REPO <terms>\`). Never create, comment on or react to anything.
- Do not open any file under the SwiftInferProperties repository's docs/, scripts/ or fixtures/ directories, nor any .json file outside your scratch directory.`

const BD_SCHEMA = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    revision: { type: 'string' },
    witness_holds: { type: 'boolean', description: 'the stated (or a corrected) call sequence returns one result twice on the census revision' },
    witness: { type: 'string', description: 'the exact sequence you confirmed, with the values each call returns' },
    trace: { type: 'string', description: 'the lines of the body that produce the repeat' },
    executed: { type: 'boolean' },
    execution_note: { type: 'string' },
    contract_allows: { type: 'string', enum: ['yes', 'no', 'unclear'], description: 'is the sequence allowed by the function/owner contract (docs, preconditions, setup requirements)?' },
    contract_reason: { type: 'string' },
    reachable: { type: 'string', enum: ['yes', 'no', 'unknown'], description: 'do real callers or user inputs in this repository produce such a sequence?' },
    reachability_reason: { type: 'string', description: 'which callers, which inputs, what the user-visible consequence is' },
    upstream_owner_repo: { type: 'string' },
    upstream_head_same: { type: 'string', enum: ['yes', 'no', 'unknown'], description: 'does the default branch still hold the same body?' },
    upstream_note: { type: 'string' },
    existing_report: { type: 'string', description: 'an existing upstream issue or PR covering it, or empty' },
    recommendation: { type: 'string', enum: ['file', 'mention-only', 'do-not-file'], description: 'file = a reachable defect worth an upstream issue; mention-only = real but unreachable or latent; do-not-file = the witness fails or the contract forbids it' },
    summary: { type: 'string', description: 'two or three sentences' },
  },
  required: ['id', 'revision', 'witness_holds', 'witness', 'trace', 'executed', 'contract_allows', 'reachable', 'reachability_reason', 'upstream_head_same', 'recommendation', 'summary'],
}

const RECHECK_SCHEMA = {
  type: 'object',
  properties: {
    rows: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          my_verdict: { type: 'string', enum: ['UNIQUIFIER', 'MEMOIZING', 'BATCH', 'LOOKUP', 'NOT-UNIQUIFIER', 'UNDETERMINED'] },
          my_expressible: { type: ['boolean', 'null'] },
          my_setup: { type: ['boolean', 'null'] },
          body_keeps_law: { type: ['boolean', 'null'], description: 'given a fresh receiver and any contract-allowed inputs, are results pairwise distinct (memoizing form for MEMOIZING)?' },
          counterexample: { type: 'string', description: 'a sequence breaking the law, or empty' },
          how_a_test_builds_it: { type: 'string', description: 'the receiver construction and input types a test would need, and whether a generator for those inputs is plausible' },
          agrees_with_judges: { type: 'boolean' },
          note: { type: 'string' },
        },
        required: ['id', 'my_verdict', 'my_expressible', 'body_keeps_law', 'agrees_with_judges', 'note'],
      },
    },
  },
  required: ['rows'],
}

const LAW = `The law (from SwiftInferProperties issue #669): "one receiver, n calls, n distinct results". Take a fresh receiver (an instance from an initialiser, or a fresh value of the inout state the function updates), call the function n times with any inputs the contract allows; the results are pairwise distinct, apart from a documented or guard-returned sentinel. A MEMOIZING uniquifier owes: equal keys give equal results, distinct keys give distinct results.`

const scratch = args.scratch

phase('Body disagrees')
const bdResults = parallel(args.bd.map((row, index) => () => agent(
  `${LAW}

Two blind judges flagged this function as one whose body breaks that law on a sequence of calls its contract allows. Your job is the hand-check that our frozen scope requires before the row is listed for possible upstream filing. Try hard to REFUTE the witness: check every line, every guard, every caller precondition. Then, if it holds, decide whether it matters.

Row:
- repository: ${row.repo} (checkout ${row.root}, census revision ${row.revision})
- file: ${row.path}, line ${row.line}; function \`${row.name}\` on \`${row.owner}\`
- judges' verdict: ${row.verdict}, expressible=${row.expressible}, setup=${row.setup}
- judges' reason: ${row.reason}
- judges' witness(es): ${row.witness}

Answer:
1. Does the witness (or a corrected one) return one result twice on the census revision? Trace it.
2. Does the function's or its owner's contract allow that sequence? (A documented precondition, a required setup call, or input restrictions stated in docs count; an unstated habit of the callers does not forbid it, but report it.)
3. Is it reachable: do this repository's real callers, or inputs a user controls (file content, names in a diagram, YAML values, tool names...), produce such a sequence, and what goes wrong visibly if so?
4. Upstream: identify OWNER/REPO from \`git -C ${row.root} remote get-url origin\`; does the default branch still hold the same body? Is there an existing issue or PR?
5. Recommend file / mention-only / do-not-file.

Your scratch directory: ${scratch}/bd-${index + 1} (create it).
${RULES}`,
  { label: `bd:${row.repo}:${row.name}`, phase: 'Body disagrees', schema: BD_SCHEMA })))

phase('Decision re-read')
const recheck = parallel(args.recheck.map((group, index) => () => agent(
  `${LAW}

An independent, UNSCORED re-read for a measurement write-up. Two blind judges read each row below and agreed on the verdict shown. The decision rule is frozen and takes their verdicts; your read is reported beside them as a disclosure and never changes the count. Read each function, its whole file and its owner's other members, and give your own answers. Be a skeptic: is this really a function that issues names/identifiers and keeps state so no call repeats an earlier result? Is the law expressible: does the contract promise it for a fresh receiver (or fresh inout value) with NOTHING else called first, constructible from the module's API (internal API via @testable import counts)? A required setup or reservation call, global/static shared state, or an unbuildable input makes it not expressible. Does the body actually keep the law for every contract-allowed input? If not, give a counterexample.

Rows:
${group.map(r => `- ${r.id}\n  checkout ${r.root} at ${r.revision}; \`${r.name}\` on \`${r.owner}\`; judges: ${r.verdict}, expressible=${r.expressible}, setup=${r.setup}, body_disagrees=${r.body_disagrees}\n  judges' reason: ${r.reason}`).join('\n')}

Your scratch directory: ${scratch}/recheck-${index + 1} (create it).
${RULES}`,
  { label: `recheck:${index + 1}`, phase: 'Decision re-read', schema: RECHECK_SCHEMA })))

const [bd, re] = await Promise.all([bdResults, recheck])
return { bd, recheck: re }
