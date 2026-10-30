export const meta = {
  name: 'hand-check-668-flagged-rows',
  description: 'Hand-check and run each #668 row flagged body disagrees or refs dangle, one agent per repository',
  phases: [
    { title: 'Hand-check', detail: 'per repository: trace each witness at the census revision, run it, read the default branch' },
  ],
}

// docs/plans/xml-emitter-census-scope.md §8: every row flagged *body disagrees* or *refs dangle* is hand-checked and
// run, then listed with its revision and offered for upstream filing. args: { scratch, groups }. Each group is one
// repository: its checkout root, census revision and flagged rows, each with the joined witness. Set `scratch` to a
// directory of your own.
const SCRATCH = args && args.scratch
const GROUPS = (args && args.groups) || []

const RULES = `Rules:
- Read source only with \`git -C <root> show <revision>:<path>\` (and \`git -C <root> grep <pattern> <revision> -- <paths>\`), so you read the census revision, not whatever the checkout holds now.
- Never build, test, edit, fetch, checkout, stash or reset inside the repository checkout. Write only under your own scratch directory, given below.
- Run each witness. Prefer, in this order: (1) export the package with \`git -C <root> archive <revision> | tar -x -C <scratch>/src\` and call the unit from a small executable or test target there, built with \`swift build -j 4\` (keep -j 4: a measurement is running on this machine); (2) when the package's build would take more than about 6 minutes or cannot build here (an app target, a platform it needs), copy the unit and exactly what it calls into a scratch script, verbatim, and run that, saying so; (3) for swift-foundation's property-list writer, the macOS Foundation's PropertyListEncoder with the XML format is the shipping build of the same code, so encoding through it counts as a run, with the census revision's body read beside it. Only if none of these is possible, trace the call line by line and say that is what it is.
- Judge the output with Foundation's XMLParser: \`XMLParser(data: Data(output.utf8)).parse()\` returning false, with its parserError, shows malformed text. For refs dangle, list every url(#X), href="#X" and xlink:href="#X" in the output and every id="X", and show the one that names no id.
- Upstream reads are allowed only read-only, with \`gh api\` (for example \`gh api repos/OWNER/REPO/contents/PATH\` for the default branch) and \`gh search issues --repo OWNER/REPO <terms>\`. Never create, comment on or react to anything.
- Do not open any file under the SwiftInferProperties repository's docs/, scripts/ or fixtures/ directories, nor any .json file outside your scratch directory.`

const ROW = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    flag: { type: 'string', enum: ['body_disagrees', 'refs_dangle'] },
    witness_holds: { type: 'boolean', description: 'the stated (or a corrected) input gives malformed text, or a dangling reference, on the census revision' },
    witness: { type: 'string', description: 'the exact input you ran and the offending part of the output' },
    parser_error: { type: 'string', description: "XMLParser's error for the output, or the dangling reference" },
    executed: { type: 'boolean' },
    execution_note: { type: 'string', description: 'how it was run: the package built, a verbatim extraction, the shipping Foundation, or a trace' },
    contract_allows: { type: 'string', enum: ['yes', 'no', 'unclear'], description: 'is that input allowed by the unit and its types and documentation?' },
    contract_reason: { type: 'string' },
    reachable: { type: 'string', enum: ['yes', 'no', 'unknown'], description: 'do real callers or user inputs reach such an input (a file name, a rule reason, a label a user types)?' },
    reachability_reason: { type: 'string' },
    upstream_owner_repo: { type: 'string' },
    upstream_head_same: { type: 'string', enum: ['yes', 'no', 'unknown'], description: 'does the default branch still hold the same defect?' },
    upstream_note: { type: 'string' },
    existing_report: { type: 'string', description: 'an existing upstream issue or PR covering it, or empty' },
    recommendation: { type: 'string', enum: ['file', 'mention-only', 'do-not-file'], description: 'file = a reachable defect worth an upstream issue; mention-only = real but unreachable or latent; do-not-file = the witness fails or the contract forbids it' },
    summary: { type: 'string', description: 'two or three sentences' },
  },
  required: ['id', 'flag', 'witness_holds', 'witness', 'parser_error', 'executed', 'execution_note', 'contract_allows',
             'reachable', 'reachability_reason', 'upstream_head_same', 'recommendation', 'summary'],
}

const SCHEMA = { type: 'object', properties: { rows: { type: 'array', items: ROW } }, required: ['rows'] }

phase('Hand-check')
const checked = await parallel(GROUPS.map(group => () => {
  const dir = `${SCRATCH}/${group.repo}`
  const rows = group.rows.map(row => `- id ${row.id}: ${row.owner ? row.owner + '.' : ''}${row.name} at ${row.path}:${row.line}; flags: ${row.body_disagrees ? 'body_disagrees' : ''}${row.refs_dangle ? ' refs_dangle (law2 OWES)' : ''}; the judges' witness: ${row.witness}`).join('\n')
  return agent(`You are hand-checking rows a blind census flagged for issue #668's laws. Law 1: a unit that builds an XML document as text returns, on every input its contract allows apart from a guard's sentinel, a document XMLParser accepts (well-formed, no character XML 1.0 forbids). Law 2 (SVG): every url(#X), href="#X" and xlink:href="#X" in the result names an id="X" in the result.\n\nRepository: ${group.repo}, checkout ${group.root}, census revision ${group.revision} (${group.group} group). Your scratch directory: ${dir}.\n\n${RULES}\n\nFor each row below, and for each flag it carries (one record per row and flag), confirm or refute the judges' witness by running it, decide whether the contract allows the input and whether real use reaches it, and read the default branch upstream. Correct a witness that fails if a close variant holds, and say so. Return one record per row and flag.\n\n${rows}`,
    { label: `handcheck:${group.repo}`, phase: 'Hand-check', schema: SCHEMA })
}))
log(`${checked.filter(Boolean).length} of ${GROUPS.length} repositories hand-checked`)
return { groups: GROUPS.map((group, i) => ({ repo: group.repo, revision: group.revision, rows: (checked[i] && checked[i].rows) || null })) }
