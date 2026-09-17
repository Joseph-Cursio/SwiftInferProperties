"""Which named seeds did the corpus funnel score as "nothing proposed" — and why?

Usage: python3 scripts/nothing_proposed_census.py <census-dir>

<census-dir> is a corpus-funnel harness directory: seeds/<repo>.json, wt/<repo>/ worktrees, and
out/<repo>/<group>/{discover.out,Generated/} with out/<repo>/groups.txt. That harness is not
committed (see docs/measurements/corpus-funnel-census-2026-09-16.md). This classifier is, because
its rules decide every count in docs/measurements/nothing-proposed-decomposition.md.

A seed counts as PROPOSED when a suggestion block names its (basename, line), or a stub's
`// Source:` header does. Everything else is written to <census-dir>/nothing.json with a cause.
"""
import glob, json, os, re, collections, sys
if len(sys.argv) != 2:
    sys.exit("usage: nothing_proposed_census.py <census-dir>")
C = os.path.abspath(sys.argv[1])
TAUT = {"determinism"}

def seeds(repo):
    try: return json.load(open(f"{C}/seeds/{repo}.json")).get("seeds", [])
    except Exception: return []

rows = []
for repo in sorted(os.listdir(f"{C}/out")):
    named = [s for s in seeds(repo) if s.get("kind") != "extractable-kernel"]
    proposed = collections.defaultdict(set)      # (basename, line) -> templates
    by_file_symbol = collections.defaultdict(set)  # (basename) -> display names seen
    lines_by_file = collections.defaultdict(set)
    for path in glob.glob(f"{C}/out/{repo}/*/discover.out"):
        for block in open(path, errors="replace").read().split("[Suggestion]")[1:]:
            t = re.search(r"Template:\s*(\S+)", block)
            if not t: continue
            for name, src, line in re.findall(r"(\S+)\s+— (\S+\.swift):(\d+)", block):
                b = os.path.basename(src)
                proposed[(b, int(line))].add(t.group(1))
                by_file_symbol[b].add(name.split("(")[0].split(".")[-1])
                lines_by_file[b].add(int(line))
    stub_sites = set()
    for path in glob.glob(f"{C}/out/{repo}/*/Generated/**/*.swift", recursive=True):
        txt = open(path, errors="replace").read()
        src = re.search(r"^// Source: (\S+\.swift):(\d+)", txt, re.M)
        if src: stub_sites.add((os.path.basename(src.group(1)), int(src.group(2))))
    groups = [l.rstrip("\n").split("\t") for l in open(f"{C}/out/{repo}/groups.txt") if "\t" in l]
    scanned_prefixes = [os.path.normpath(os.path.join(p, s)) for p, s in groups]
    basenames = collections.Counter(os.path.basename(s["file"]) for s in named)

    for s in named:
        b, line = os.path.basename(s["file"]), s["line"]
        if proposed.get((b, line)) or (b, line) in stub_sites: continue
        rel = os.path.normpath(s["file"])
        src_path = f"{C}/wt/{repo}/{rel}"
        decl = ""
        if os.path.exists(src_path):
            L = open(src_path, errors="replace").read().split("\n")
            decl = " ".join(x.strip() for x in L[line-1:line+2])
        if not any(rel == p or rel.startswith(p + "/") for p in scanned_prefixes):
            cause = "file in no scan group"
        elif s["symbol"] in by_file_symbol.get(b, set()):
            near = min((abs(l - line) for l in lines_by_file[b]), default=999)
            cause = f"join miss: symbol proposed in same file (nearest line ±{near})"
        else:
            cause = "no suggestion for this symbol"
        rows.append(dict(repo=repo, kind=s.get("kind"), role=s.get("role"), symbol=s["symbol"],
                         file=rel, line=line, cause=cause, decl=decl[:160], dup=basenames[b] > 1))

def fallback_gate(r):
    """Which determinism-fallback gate (Discover+GenericLaws.qualifiesForDeterminism) a
    pure-function seed with nothing proposed falls to. Read off the declaration's text, ordered;
    the first match wins. A read-only computed property is summarised as a NULLARY method
    (FunctionScannerVisitor+Summary.makeSummary(fromComputedProperty:), `parameters: []`), so it
    reaches the fallback and is rejected at `parameters.isEmpty == false`."""
    path = f"{C}/wt/{r['repo']}/{r['file']}"
    if not os.path.exists(path):
        return "source missing"
    lines = open(path, errors="replace").read().split("\n")
    text = " ".join(x.strip() for x in lines[r["line"] - 1:r["line"] + 12])
    sig = text.split("{")[0]
    if re.search(r"\bvar\s+\w+\s*:", sig) and not re.search(r"\bfunc\b", sig):
        return "no-parameters gate: a computed property, summarised as nullary"
    if not re.search(r"\bfunc\b", sig):
        return "not a function or property at the seed line"
    body = open(path, errors="replace").read()
    params = re.search(r"\(([^)]*)\)", sig.split("func", 1)[-1])
    ret = re.search(r"->\s*(.+)$", sig)
    if not ret or ret.group(1).strip() in ("Void", "()"):
        return "Void-return gate"
    if params and params.group(1).strip() == "":
        return "no-parameters gate: a nullary method"
    if re.search(r"\basync\b", sig):
        return "async gate"
    if len(re.findall(r"\bfunc\s+" + re.escape(r["symbol"]) + r"\s*[(<]", body)) > 1:
        return "(file, symbol) key shared with a same-named overload"
    return "passes every gate, no overload"

for r in rows:
    if r["kind"] == "pure-function":
        r["gate"] = fallback_gate(r)

json.dump(rows, open(f"{C}/nothing.json", "w"), indent=1)
print("classified:", len(rows))
cc = collections.Counter(r["cause"].split(" (")[0] for r in rows)
for k, v in cc.most_common(): print(f"  {v:5}  {k}")
print("\nby seed kind:")
for k, v in collections.Counter(r["kind"] for r in rows).most_common(): print(f"  {v:5}  {k}")
print("\npure-function seeds, by the determinism-fallback gate they fall to:")
for k, v in collections.Counter(r["gate"] for r in rows if "gate" in r).most_common(): print(f"  {v:5}  {k}")
