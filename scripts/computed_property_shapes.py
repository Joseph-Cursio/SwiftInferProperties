"""Characterise the computed properties the funnel seeded and nothing proposed a law for.

Usage: python3 scripts/computed_property_shapes.py <census-dir>  (after nothing_proposed_census.py)

For each: the enclosing type (kind, name, inheritance clause), the declared type, and the
getter body brace-matched out of the source — then a body-shape bucket. Rules are ordered and
the FIRST match wins, so the order is part of the definition and is printed with the result.
"""
import json, os, re, collections, sys
if len(sys.argv) != 2:
    sys.exit("usage: computed_property_shapes.py <census-dir>")
C = os.path.abspath(sys.argv[1])

def strip_strings_and_comments(text):
    """Blank out string literals and comments, keeping offsets, so braces inside them don't count."""
    out = list(text); i = 0; n = len(text)
    while i < n:
        if text.startswith('"""', i):
            j = text.find('"""', i + 3); j = n if j < 0 else j + 3
            for k in range(i + 3, max(i + 3, j - 3)): out[k] = " " if text[k] != "\n" else "\n"
            i = j; continue
        if text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            for k in range(i + 1, min(j, n)): out[k] = " "
            i = j + 1; continue
        if text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j
            for k in range(i, j): out[k] = " "
            i = j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            for k in range(i, j): out[k] = " " if text[k] != "\n" else "\n"
            i = j; continue
        i += 1
    return "".join(out)

TYPE_DECL = re.compile(r"\b(struct|enum|class|actor|extension|protocol)\s+([\w.]+)([^{]*)\{")

def analyse(path, line):
    raw = open(path, errors="replace").read()
    code = strip_strings_and_comments(raw)
    starts = [0]
    for m in re.finditer("\n", raw): starts.append(m.end())
    pos = starts[line - 1]
    decl = re.compile(r"\bvar\s+(\w+)\s*:\s*([^{=]+?)\s*\{").search(code, pos)
    if not decl or decl.start() - pos > 400: return None
    open_i = decl.end() - 1; depth = 0; close_i = None
    for k in range(open_i, len(code)):
        if code[k] == "{": depth += 1
        elif code[k] == "}":
            depth -= 1
            if depth == 0: close_i = k; break
    body = raw[open_i + 1:close_i].strip() if close_i else ""
    # enclosing type: innermost TYPE_DECL whose block contains the property
    enclosing = None
    for m in TYPE_DECL.finditer(code, 0, decl.start()):
        d = 0; end = None
        for k in range(m.end() - 1, len(code)):
            if code[k] == "{": d += 1
            elif code[k] == "}":
                d -= 1
                if d == 0: end = k; break
        if end and end > decl.start(): enclosing = m
    kind, tname, clause = (enclosing.group(1), enclosing.group(2), enclosing.group(3)) if enclosing else (None, None, "")
    inherits = [x.strip().split("<")[0] for x in clause.split(":", 1)[1].split("where")[0].split(",")] if ":" in clause else []
    return dict(name=decl.group(1), type=decl.group(2).strip(), body=body, kind=kind, typeName=tname,
                inherits=[x for x in inherits if x])

def body_shape(p):
    b = re.sub(r"^\s*get\s*\{(.*)\}\s*$", r"\1", p["body"], flags=re.S).strip()
    one = b.removeprefix("return ").strip()
    lines = [l for l in b.split("\n") if l.strip()]
    if re.match(r"^(switch\s+self\b)", b): return "switch self — a per-case mapping"
    if re.search(r"\bswitch\s+self\b", b): return "switch self — a per-case mapping"
    if len(lines) == 1 and re.fullmatch(r'(true|false|nil|-?\d+(\.\d+)?|"[^"\\]*"|\[\]|\[:\]|\.\w+)', one):
        return "a literal constant"
    if len(lines) == 1 and re.fullmatch(r"[\w.?!]+", one): return "forwards another member"
    if len(lines) == 1 and re.search(r"\.(isEmpty|count|contains|first|last|filter|map|compactMap|reduce|allSatisfy|sorted)\b", one):
        return "derived from a collection"
    if len(lines) == 1 and re.search(r"(&&|\|\||==|!=|<=|>=|\s<\s|\s>\s|^!)", one) and not re.search(r'"', one):
        return "a boolean or comparison over other state"
    if re.search(r'\\\(|\.joined\(|String\(format:|\+\s*"|"\s*\+', b): return "formats a string"
    if len(lines) == 1: return "other single expression"
    return "other multi-statement body"

REQUIREMENT = {
    "description": "CustomStringConvertible", "debugDescription": "CustomDebugStringConvertible",
    "errorDescription": "LocalizedError", "failureReason": "LocalizedError",
    "recoverySuggestion": "LocalizedError", "helpAnchor": "LocalizedError",
    "id": "Identifiable", "body": "View", "hashValue": "Hashable",
}

if __name__ == "__main__":
    rows = [r for r in json.load(open(f"{C}/nothing.json")) if r["kind"] == "pure-function"]
    out = []
    for r in rows:
        path = f"{C}/wt/{r['repo']}/{r['file']}"
        if not os.path.exists(path): continue
        head = " ".join(open(path, errors="replace").read().split("\n")[r["line"] - 1:r["line"] + 1])
        if not re.search(r"\bvar\s+\w+\s*:", head) or re.search(r"\bfunc\b", head): continue
        p = analyse(path, r["line"])
        if not p: continue
        p.update(repo=r["repo"], file=r["file"], line=r["line"], shape=body_shape(p),
                 requirement=REQUIREMENT.get(p["name"]))
        out.append(p)
    json.dump(out, open(f"{C}/props.json", "w"), indent=1)
    print("computed properties characterised:", len(out))
