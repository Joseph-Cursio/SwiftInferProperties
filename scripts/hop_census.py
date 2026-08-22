"""LOWER-BOUND sizing census, regex-based and FILE-scoped, not type-scoped.

Question: how many initialisers call a same-file helper METHOD whose own body
contains a precondition call? That is the hop `InitializerPreconditionDetector`
does not follow (it follows init -> init, not init -> method).

Deliberately approximate. Reported as a lower bound for deciding whether a real
SwiftSyntax instrument is worth building -- NOT as an answer.
"""
import json, os, re, sys, collections

PRECOND = re.compile(r'\b(assert|precondition|assertionFailure|preconditionFailure|fatalError)\s*\(')
FUNC = re.compile(r'^\s*(?:@\w+\s+)*(?:public |internal |private |fileprivate |package )?'
                  r'(?:static |class |mutating |final )*func\s+(\w+)\s*\(', re.M)
INIT = re.compile(r'^\s*(?:@\w+\s+)*(?:public |internal |private |fileprivate |package )?'
                  r'(?:convenience |required )*init[?!]?\s*[<(]', re.M)

def block_at(text, start):
    """Body from the first '{' after start to its matching '}'."""
    i = text.find('{', start)
    if i < 0: return ''
    depth, j = 0, i
    while j < len(text):
        if text[j] == '{': depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0: return text[i:j+1]
        j += 1
    return text[i:]

def scan(path):
    hits = []
    for root, _, files in os.walk(path):
        if any(p in root for p in ('/.build', '/.git', '/Tests', '/test')): continue
        for fn in files:
            if not fn.endswith('.swift'): continue
            fp = os.path.join(root, fn)
            try: text = open(fp, encoding='utf-8', errors='ignore').read()
            except Exception: continue
            # methods in this file whose body asserts
            asserting = set()
            for m in FUNC.finditer(text):
                if PRECOND.search(block_at(text, m.end())): asserting.add(m.group(1))
            if not asserting: continue
            for m in INIT.finditer(text):
                body = block_at(text, m.end())
                if PRECOND.search(body): continue          # already caught directly
                called = set(re.findall(r'\b(\w+)\s*\(', body))
                hit = called & asserting
                if hit: hits.append((fp, sorted(hit)))
    return hits

m = json.load(open('fixtures/corpora/manifest.json'))
total, per = 0, []
for c in m['corpora']:
    lp = c.get('localPath')
    if not lp: continue
    p = os.path.expanduser(lp)
    if not os.path.isabs(p): p = os.path.abspath(p)
    if not os.path.isdir(p): continue
    h = scan(p)
    total += len(h)
    if h: per.append((c['id'], len(h), h[:2]))
per.sort(key=lambda t: -t[1])
for cid, n, sample in per:
    print(f"{n:>5}  {cid}")
    for fp, hit in sample:
        print(f"          e.g. {os.path.basename(fp)} -> {', '.join(hit)}")
print(f"\nLOWER BOUND, init -> same-file asserting method: {total}")
