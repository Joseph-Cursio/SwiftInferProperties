export const meta = {
  name: 'equivalence-667-survivors',
  description: 'Read the 36 kill-arm mutants no test detected for equivalence and law reach (#667 scope §5.6)',
  phases: [{ title: 'Judge' }, { title: 'Decide splits' }, { title: 'Refute' }],
}

// docs/plans/layering-law-census-scope.md §5.6: the equivalence reading of the 36 mutants that neither the law
// nor the full suite detected. args: those mutants grouped by function, each { id, path (EXPORT/...), line,
// function, operator, original, replacement, before, after }. As run, EXPORT_DIR named the c6c82e3 export in the
// session's scratch directory, so set it to your own. Two readers read each group, a third reads any mutant whose
// verdict or law reach they split on, and a refuter checks every EQUIVALENT verdict and every claimed law witness.
const RULES = `You are reading mutants of a Swift library for EQUIVALENCE. Each mutant is one small edit to a
function in SwiftUMLStudio's SwiftUMLBridgeFramework, as exported at commit c6c82e3. No test detected any of
these mutants. Your job is to say, for each, whether the edit can change anything observable.

What you may read: Swift source files under the export directory that contains the file you are given (its
SwiftUMLBridge/Sources and SwiftUMLBridge/Tests). Read the whole function, its callers and callees in the
library, and the types it returns. Do NOT edit, create or delete any file; do NOT run swift, swift build,
swift test or xcodebuild. You may run python3 for arithmetic. Do not read anything outside that export.

The library API involved:
- ActivitySVGRenderer.computeLayout(from: ActivityGraph) returns an activity layout: nodes with centre x/y,
  width, height, plus total width and height. computeRows(graph:) gives each node a row; computeColumns gives
  each node a column within its row.
- ComponentSVGRenderer.computeLayout(_ model: ComponentModel) returns a component layout: components with
  centre x/y, width, height, plus a canvas width and height. dependencyLevels / chainDepth group components
  into rows; boxSize(for:) sizes one box.
The SVG renderers turn these layouts into SVG text.

For EACH mutant decide:
- verdict:
  * EQUIVALENT: for EVERY input the library can construct (any graph or model, not only typical ones), the
    mutated code produces exactly the same observable values (every field of the returned layout, and
    therefore the same SVG). A change that only affects performance (e.g. removing reserveCapacity) is
    EQUIVALENT. Floating-point results must be identical, not merely close.
  * NOT-EQUIVALENT: some input makes an observable value differ. Give the smallest concrete input you can
    (nodes, edges / components, dependencies, interfaces) and name the field that differs, with its value
    before and after the edit, computed from the code's actual constants.
  * UNDETERMINED: the source does not let you decide.
- changes: what the edit affects, one of: none, x-position, width-or-height, canvas-or-total-size,
  vertical-shift-uniform (every centre y moves by the same amount), vertical-order-preserving (centre y values
  change but their order across every edge never flips), vertical-order-can-flip, rows-or-levels, label-text,
  other.
- law_reachable: the layering law has three checks, each over a randomly drawn graph:
  L1: for every edge u -> v reachable from the start node with v unable to reach u, row(v) > row(u)
      (computeRows).
  L2: the same edges, with activity computeLayout's node centerY: centerY(v) > centerY(u).
  L3: for every component dependency from -> to with 'to' unable to reach 'from', the component centerY of
      'to' > centerY of 'from' (component computeLayout).
  A covered edge whose endpoint is missing from the result also fails. Set law_reachable = true only if you can
  give a concrete input on which the MUTATED code fails L1, L2 or L3 (the unmutated code passes all three);
  put that input in law_witness. Otherwise false, and say why the law cannot see the edit.
- reason: a short explanation that cites the code.`

const RESULT = {
  type: 'object',
  properties: {
    mutants: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['EQUIVALENT', 'NOT-EQUIVALENT', 'UNDETERMINED'] },
          witness: { type: 'string' },
          changes: { type: 'string' },
          law_reachable: { type: 'boolean' },
          law_witness: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['id', 'verdict', 'changes', 'law_reachable', 'reason'],
      },
    },
  },
  required: ['mutants'],
}

const REFUTE = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    input: { type: 'string' },
    evidence: { type: 'string' },
  },
  required: ['refuted', 'evidence'],
}

const EXPORT_DIR = '<export>/'
const describe = m => `${m.id}: ${m.path.replace('EXPORT/', EXPORT_DIR)} line ${m.line}, function ${m.function}, operator ${m.operator}\n  before: ${m.before}\n  after:  ${m.after}`

const groups = args
const results = await pipeline(
  groups,
  group => parallel(['A', 'B'].map(judge => () =>
    agent(`${RULES}\n\nThe mutants (each is applied ALONE to the unmutated file):\n${group.mutants.map(describe).join('\n')}\n\nReturn one entry per mutant id.`,
      { label: `judge-${judge}:${group.name}`, phase: 'Judge', schema: RESULT }))),
  async (pair, group) => {
    const byId = side => Object.fromEntries(((side && side.mutants) || []).map(v => [v.id, v]))
    const a = byId(pair[0]), b = byId(pair[1])
    const split = group.mutants.filter(m => !a[m.id] || !b[m.id] || a[m.id].verdict !== b[m.id].verdict
      || a[m.id].law_reachable !== b[m.id].law_reachable)
    let c = {}
    if (split.length) {
      c = byId(await agent(`${RULES}\n\nThe mutants (each is applied ALONE to the unmutated file):\n${split.map(describe).join('\n')}\n\nReturn one entry per mutant id.`,
        { label: `judge-C:${group.name}`, phase: 'Decide splits', schema: RESULT }))
    }
    return group.mutants.map(m => ({ mutant: m, A: a[m.id] || null, B: b[m.id] || null, C: c[m.id] || null }))
  },
  async rows => {
    const finalOf = row => {
      const votes = [row.A, row.B, row.C].filter(Boolean)
      const count = key => votes.filter(v => v.verdict === key).length
      const verdict = ['EQUIVALENT', 'NOT-EQUIVALENT', 'UNDETERMINED'].find(key => count(key) >= 2) || 'SPLIT'
      const reach = votes.filter(v => v.law_reachable).length >= 2 ? true
        : votes.filter(v => v.law_reachable === false).length >= 2 ? false : null
      return { verdict, reach }
    }
    return parallel(rows.map(row => async () => {
      const fin = finalOf(row)
      const checks = []
      if (fin.verdict === 'EQUIVALENT') {
        checks.push(agent(`${RULES}\n\nTwo readers judged this mutant EQUIVALENT. Try hard to REFUTE that: find a concrete input the library can construct on which the mutated code returns a different value in any field of the layout. Compute both values from the code's actual constants. Set refuted = true only with such an input.\n\n${describe(row.mutant)}`,
          { label: `refute-equivalent:${row.mutant.id}`, phase: 'Refute', schema: REFUTE }))
      }
      if (fin.reach === true) {
        const witness = [row.A, row.B, row.C].filter(v => v && v.law_reachable).map(v => v.law_witness).join('\n---\n')
        checks.push(agent(`${RULES}\n\nReaders claimed the layering law (L1/L2/L3 above) can detect this mutant, with these witnesses:\n${witness}\n\nCheck a witness by computing, from the actual code, every covered edge's values before and after the edit. Set refuted = true if NO witness makes the mutated code fail L1, L2 or L3 while the unmutated code passes.\n\n${describe(row.mutant)}`,
          { label: `check-reach:${row.mutant.id}`, phase: 'Refute', schema: REFUTE }))
      }
      const verdicts = await Promise.all(checks)
      return { ...row, final: fin, refutations: verdicts }
    }))
  },
)
return results.filter(Boolean).flat()
