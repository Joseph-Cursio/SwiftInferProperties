export const meta = {
  name: 'judge-667-layering',
  description: 'Blind hand-check of #667 layering-census rows: calibration, two judges per packet, a third on a split',
  phases: [{ title: 'Calibrate' }, { title: 'Judge' }, { title: 'Decide splits' }],
}

// docs/plans/layering-law-census-scope.md §4. args: { calibration, packets: [{ name, path, labels }] }, every path
// in a directory that holds the packets and nothing else. Judges see a packet and these rules only: never the cues,
// GATED, group, stratum, predictions, §8, any count, or the expected calibration answers below.
const RULES = `You are a judge in a blind hand-check for a code census. Each row below is one Swift function a
mechanical scan found. For EACH row, decide which verdict applies. Read the row's text and docs.

What you may read: the packet file you are given, and, for context, source files under the row's own
repository path (given in the row). Nothing else. In particular: never open, list or search any directory
named docs, scripts or fixtures inside a repository whose name starts with SwiftInferProperties (a row there
may be read only through its own file); never open any .json file; never open any other packet; and never
search for a function's name outside the row's own repository. Judge the function's own contract.
Do not edit any file.

Verdicts, exactly one per row:
- LAYERING: the function gives each node of a directed graph an integer layer or a position along one axis,
  or groups the nodes into an ordered list of levels. Its contract is that across every edge not on a cycle,
  among the nodes it layers, the layer strictly increases in one consistent direction. The graph must admit a
  node with two or more predecessors (a DAG or general digraph, not a tree).
  * A contract stated by the name or the documentation is enough. A body that contradicts it is still
    LAYERING: set body_disagrees = true.
  * A longest-path depth (one plus the maximum over predecessors, or over successors) is LAYERING, whichever
    way it counts.
  * An ordered list of groups ([[T]], [Set<T>], [Int: [T]]) is LAYERING when every off-cycle edge goes from an
    earlier group to a strictly later one, or the reverse throughout.
- TREE-DEPTH: the same, over a tree, where each node has at most one parent: depth(child) = depth(parent) + 1.
- ORDERING: a FLAT sequence of the nodes in an order meant to respect the edges (a topological sort or its
  reverse).
- NOT-LAYERING: anything else; give a short reason. Breadth-first or shortest-path distance is NOT-LAYERING
  (on r->a, r->b, a->b it gives d(a) == d(b)), as are syntax nesting depth, indentation, table rows, a sort's
  rank, a CALayer. A function that only reads or forwards a layering computed elsewhere is NOT-LAYERING with
  reason "reads a layering".
- UNDETERMINED: the text does not decide it.

For LAYERING only, also record:
- result_kind: one of map, per-node query, coordinate, levels;
- direction: the edge direction it claims;
- excluded: which nodes it leaves out (e.g. unreachable ones), or "none";
- expressible: true only when (1) the edges can be enumerated from the function's inputs, (2) the root, if the
  layering needs one, can be identified from the inputs, and (3) the law holds for the function called by
  itself, without a cache or state shared with other calls.
- body_disagrees: true when the body does not do what the name or documentation states.`

const VERDICTS = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          verdict: { type: 'string', enum: ['LAYERING', 'TREE-DEPTH', 'ORDERING', 'NOT-LAYERING', 'UNDETERMINED'] },
          reason: { type: 'string' },
          result_kind: { type: 'string' },
          direction: { type: 'string' },
          excluded: { type: 'string' },
          expressible: { type: 'boolean' },
          body_disagrees: { type: 'boolean' },
        },
        required: ['label', 'verdict', 'reason'],
      },
    },
  },
  required: ['verdicts'],
}

// §4.2's expected calibration answers. A judge never sees them.
const EXPECTED = {
  'calibration/1': { verdict: 'LAYERING', result_kind: 'map', expressible: true },
  'calibration/2': { verdict: 'LAYERING', body_disagrees: true },
  'calibration/3': { verdict: 'LAYERING', result_kind: 'levels', expressible: true },
  'calibration/4': { verdict: 'NOT-LAYERING' },
  'calibration/5': { verdict: 'NOT-LAYERING' },
  'calibration/6': { verdict: 'ORDERING' },
  'calibration/7': { verdict: 'TREE-DEPTH' },
  'calibration/8': { verdict: 'LAYERING', expressible: false },
}
const CAL_LABELS = Object.keys(EXPECTED)

phase('Calibrate')
const calibration = await parallel(['A', 'B'].map(judge => () =>
  agent(`${RULES}\n\nRead the packet file ${args.calibration}. It holds ${CAL_LABELS.length} rows labelled ${CAL_LABELS.join(', ')}. Return one verdict per label.`,
    { label: `calibrate-${judge}`, phase: 'Calibrate', schema: VERDICTS })))
const misses = []
calibration.forEach((side, index) => {
  const got = Object.fromEntries(((side && side.verdicts) || []).map(v => [v.label, v]))
  for (const [label, want] of Object.entries(EXPECTED)) {
    const answer = got[label]
    const wrong = !answer || Object.entries(want).some(([field, value]) =>
      field === 'result_kind' ? !(answer.result_kind || '').toLowerCase().includes(value) : answer[field] !== value)
    if (wrong) misses.push({ judge: index ? 'B' : 'A', label, want, got: answer || null })
  }
})
if (misses.length) {
  log(`calibration missed ${misses.length} answers: the arm stops (§4.2)`)
  return { calibration: { passed: false, misses, answers: calibration }, judgements: [] }
}
log(`calibration passed: both judges matched all ${CAL_LABELS.length} items`)

const judgements = await pipeline(
  args.packets,
  packet => parallel(['A', 'B'].map(judge => () =>
    agent(`${RULES}\n\nRead the packet file ${packet.path}. It holds ${packet.labels.length} rows labelled ${packet.labels.join(', ')}. Return one verdict per label.`,
      { label: `judge-${judge}:${packet.name}`, phase: 'Judge', schema: VERDICTS }))),
  async (pair, packet) => {
    const byLabel = side => Object.fromEntries(((side && side.verdicts) || []).map(v => [v.label, v]))
    const a = byLabel(pair[0]), b = byLabel(pair[1])
    // A LAYERING verdict that does not answer EXPRESSIBLE is no answer, so it goes to the third judge too.
    const unanswered = v => v.verdict === 'LAYERING' && typeof v.expressible !== 'boolean'
    const split = packet.labels.filter(label => !a[label] || !b[label] || a[label].verdict !== b[label].verdict
      || unanswered(a[label]) || unanswered(b[label])
      || (a[label].verdict === 'LAYERING' && a[label].expressible !== b[label].expressible))
    let c = {}
    if (split.length) {
      c = byLabel(await agent(`${RULES}\n\nRead the packet file ${packet.path}. Judge ONLY these rows: ${split.join(', ')}. Return one verdict per label.`,
        { label: `judge-C:${packet.name}`, phase: 'Decide splits', schema: VERDICTS }))
    }
    return packet.labels.map(label => ({ label, A: a[label] || null, B: b[label] || null, C: c[label] || null }))
  },
)
return { calibration: { passed: true, answers: calibration }, judgements: judgements.filter(Boolean).flat() }
