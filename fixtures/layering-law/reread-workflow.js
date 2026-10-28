// #667's graph-layout corpus, beside the frozen decision (docs/measurements/layering-law-census.md, 2026-10-28
// section): three refuters per row judged LAYERING and EXPRESSIBLE, and two counterexample builders per row on the
// body-disagrees line. args: the rows, as [{ id, root, path, line, name, result_kind, direction, excluded,
// body_disagrees }]. It never changes the decision; its output is reread-graph-layout-2026-10-28.json.

export const meta = {
  name: 'verify-667-corpus-layerings',
  description: 'Adversarially re-read the corpus rows judged LAYERING and EXPRESSIBLE, and test the two body-disagrees flags',
  phases: [{ title: 'Refute' }, { title: 'Counterexample' }],
}

const RULES = `Definitions (the census's verdict rules):
- LAYERING: the function gives each node of a directed graph an integer layer or a position along one axis, or
  groups the nodes into an ordered list of levels. Its contract is that across every edge not on a cycle, among
  the nodes it layers, the layer strictly increases in one consistent direction. The graph must admit a node with
  two or more predecessors (a DAG or general digraph, not a tree). A contract stated by the name or the
  documentation is enough; a body that contradicts it is still LAYERING but flagged body_disagrees. A
  longest-path depth (1 + max over predecessors, or successors) is LAYERING. An ordered list of groups is
  LAYERING when every off-cycle edge goes from an earlier group to a strictly later one (or the reverse
  throughout).
- NOT a layering: breadth-first / shortest-path distance (on r->a, r->b, a->b it gives d(a) == d(b)); a function
  that only reads or forwards a layering computed elsewhere ("reads a layering"); a position that is not ordered
  along the edges; a contract that allows an off-cycle edge to keep the same layer (non-strict) in general use;
  syntax depth, table rows, a sort's rank.
- TREE-DEPTH: the same over a tree (each node at most one parent). ORDERING: a flat sequence (topological sort).
- EXPRESSIBLE: (1) the edges can be enumerated from the function's inputs; (2) the root, if the layering needs
  one, can be identified from the inputs; (3) the law holds for the function called by itself, without a cache or
  state shared with other calls.`

const LIMITS = `What you may read: Swift source files under the row's repository root only. Do not edit, create or delete
any file there. Do not run swift, swift build, swift test or xcodebuild, and do not run any code from the repository.
You may run python3 for arithmetic or to simulate the function on a small input you write yourself. Never open
anything under a directory named SwiftInferProperties*.`

const VERDICT = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['CONFIRMED', 'NOT-LAYERING', 'NOT-EXPRESSIBLE', 'UNSURE'] },
    better_verdict: { type: 'string' },
    evidence: { type: 'string' },
    counterexample: { type: 'string' },
  },
  required: ['verdict', 'evidence'],
}
const COUNTER = {
  type: 'object',
  properties: {
    doc_states_layering: { type: 'boolean' },
    counterexample_found: { type: 'boolean' },
    input: { type: 'string' },
    computed_values: { type: 'string' },
    evidence: { type: 'string' },
  },
  required: ['doc_states_layering', 'counterexample_found', 'evidence'],
}

const describe = row => `Row: function \`${row.name}\` at ${row.root}/${row.path} line ${row.line} (repository root ${row.root}).`

const results = await pipeline(
  args,
  row => parallel(['1', '2', '3'].map(n => () => agent(
    `${RULES}\n\n${LIMITS}\n\n${describe(row)}\n\nBlind judges classified this function LAYERING and EXPRESSIBLE, with result kind "${row.result_kind}", direction "${row.direction}", excluded "${row.excluded}".\n\nYour job is to try hard to REFUTE that, reading the function, its callers and callees, and its types in that repository. Return NOT-LAYERING (say which verdict fits better in better_verdict and why), NOT-EXPRESSIBLE (name the failed clause), CONFIRMED (only if you checked the contract holds across every off-cycle edge, citing code), or UNSURE. Where you refute, give a concrete counterexample input and the values the code computes for it when you can.`,
    { label: `refute-${n}:${row.name}@${row.path.split('/').pop()}`, phase: 'Refute', schema: VERDICT }))),
  async (votes, row) => {
    const counter = row.body_disagrees ? await parallel(['1', '2'].map(n => () => agent(
      `${RULES}\n\n${LIMITS}\n\n${describe(row)}\n\nA judge flagged that this function's BODY does not do what its name or documentation states (a layering with direction "${row.direction}"). Check two things. (a) Does the name or the doc comment actually state a layering contract (strictly increasing across every off-cycle edge)? Quote it. (b) Construct the smallest concrete input you can on which the body, as written, places an off-cycle edge's target at a layer or coordinate not strictly beyond its source (in the stated direction). Compute every relevant value from the code's actual constants, simulating in python3 if useful. counterexample_found = true only with such an input and its computed values.`,
      { label: `counter-${n}:${row.name}@${row.path.split('/').pop()}`, phase: 'Counterexample', schema: COUNTER }))) : []
    return { row, votes, counter }
  },
)
return results