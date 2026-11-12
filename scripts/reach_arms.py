#!/usr/bin/env python3
"""#684's arms: one funnel and one reach census per arm, over pinned trees.

`docs/plans/predicate-reach-at-source-scope.md` §3 freezes the arms, the pins and the binary. Every arm
runs the same `swift-infer` binary; only `SWIFT_INFER_REACH_ARM` differs. This wrapper keeps the steps
identical across arms, so a difference between two arms' rows is the switch and nothing else.

    reach_arms.py prepare <run-dir>                       # trees/<repo> at the pinned SHAs
    reach_arms.py funnel  <run-dir> <arm> <swift-infer> <cli>
    reach_arms.py census  <run-dir> <arm> <out.jsonl> --swift-infer <sha> --cli <sha>
    reach_arms.py cost    <run-dir>                       # corpus snippets and bytes per package
    reach_arms.py all     <run-dir> <arm> <swift-infer> <cli> <fixture.jsonl> --swift-infer-sha <sha> --cli-sha <sha>
    reach_arms.py --self-test
"""

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIBLINGS = os.path.dirname(ROOT)

# §3, recorded 2026-11-12 before any lever code. #665's 19, in its order.
PINS = {
    "SwiftMarkdownWiki": "51b789e", "SwiftProjectLint": "6a231cda", "SwiftAssist": "8e1bc8d",
    "SwiftPropertyLaws": "b45d1bf", "SwiftUMLStudio": "9ad7631", "SwiftLintRuleStudio": "77cc792",
    "pbt-workbook-corpus": "6df2650", "pbt-book": "3e76194", "SwiftFormatRuleStudio": "5cea6a7",
    "SwiftEffectInference": "5e981ca", "SwiftLintRuleStudioTeam": "7789bde", "MacCloud_client_MacOS": "9424f4f",
    "SwiftCloneDetector": "e03e865", "pbt-workbook-sampler": "0e07795", "LintStudioUI": "abcff42",
    "MacCloud_server": "b0a1495", "SwiftIdempotency": "adf8d18", "pbt-workbook": "959937e",
    "pbt-workbook-grader": "79e6c81",
}
ARMS = {"baseline", "uncapped", "seeded", "baseline+paired", "uncapped+paired", "seeded+paired"}
CORPUS_FILE = "SwiftInferSyntaxCorpus.swift"
SNIPPET_OPEN = re.compile(r'^\s+(#+)"""$', re.M)


def tree_path(run, repo):
    return os.path.join(run, "trees", repo)


def prepare(run, pins=PINS, siblings=SIBLINGS):
    """A detached worktree per repository at its pinned SHA. `corpus_funnel.worktree` reuses an existing
    directory, so the funnel then walks these trees rather than each sibling's HEAD."""
    made = []
    for repo, sha in pins.items():
        destination = tree_path(run, repo)
        if os.path.isdir(destination):
            head = subprocess.run(["git", "-C", destination, "rev-parse", "--short", "HEAD"],
                                  capture_output=True, text=True, check=True).stdout.strip()
            if not sha.startswith(head) and not head.startswith(sha):
                raise SystemExit(f"{destination} is at {head}, not the pinned {sha}")
            continue
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        subprocess.run(["git", "-C", os.path.join(siblings, repo), "worktree", "add", "-q", "--detach",
                        destination, sha], check=True, capture_output=True)
        made.append(repo)
    return made


def arm_environment(arm, base=None):
    if arm not in ARMS:
        raise SystemExit(f"{arm} is not an arm: {sorted(ARMS)}")
    env = dict(os.environ if base is None else base)
    env.pop("SWIFT_DETERMINISTIC_HASHING", None)
    env["SWIFT_INFER_REACH_ARM"] = arm
    return env


def claim(run, arm):
    """Records `run`'s arm, and refuses a second one: the funnel skips a repository whose result file
    exists, so a reused directory would hand the earlier arm's stubs to the census under the new label."""
    os.makedirs(run, exist_ok=True)
    marker = os.path.join(run, "arm.txt")
    if os.path.exists(marker):
        recorded = open(marker, encoding="utf-8").read().strip()
        if recorded != arm:
            raise SystemExit(f"{run} holds arm {recorded}, not {arm}")
    else:
        open(marker, "w", encoding="utf-8").write(arm + "\n")


def funnel(run, arm, infer, cli):
    claim(run, arm)
    prepare(run)
    command = [sys.executable, os.path.join(HERE, "corpus_funnel.py"), run, infer, cli, *PINS]
    with open(os.path.join(run, "funnel.log"), "a", encoding="utf-8") as log:
        return subprocess.run(command, cwd=ROOT, env=arm_environment(arm), stdout=log,
                              stderr=subprocess.STDOUT).returncode


def census(run, arm, out, swift_infer, cli):
    claim(run, arm)
    command = [sys.executable, os.path.join(HERE, "predicate_outcome_reach.py"), "run", run, out,
               "--arm", arm, "--swift-infer", swift_infer, "--cli", cli, *PINS]
    with open(os.path.join(run, "census.log"), "a", encoding="utf-8") as log:
        return subprocess.run(command, cwd=ROOT, env=arm_environment(arm), stdout=log,
                              stderr=subprocess.STDOUT).returncode


def corpus_cost(text):
    return {"snippets": len(SNIPPET_OPEN.findall(text)), "bytes": len(text.encode("utf-8"))}


def cost(run):
    """Every corpus file the funnel wrote, by package: snippets and bytes (§4)."""
    found = {}
    for dirpath, dirs, files in os.walk(os.path.join(run, "trees")):
        dirs[:] = [d for d in dirs if d not in (".build", ".git")]
        if CORPUS_FILE in files:
            path = os.path.join(dirpath, CORPUS_FILE)
            found[os.path.relpath(path, run)] = corpus_cost(open(path, encoding="utf-8").read())
    return found


def self_test():
    failures = []
    text = 'enum C {\n    static let snippets: [String] = [\n        #"""\nfunc f() {}\n"""#,\n' \
           '        ##"""\nlet s = """#\n"""##\n    ]\n}\n'
    if corpus_cost(text)["snippets"] != 2:
        failures.append(f"corpus_cost: {corpus_cost(text)}")
    env = arm_environment("seeded+paired", {"SWIFT_DETERMINISTIC_HASHING": "1", "PATH": "/bin"})
    if env.get("SWIFT_INFER_REACH_ARM") != "seeded+paired" or "SWIFT_DETERMINISTIC_HASHING" in env:
        failures.append(f"arm_environment: {env}")
    try:
        arm_environment("seed")
        failures.append("arm_environment accepted an unknown arm")
    except SystemExit:
        pass
    import tempfile
    with tempfile.TemporaryDirectory() as run:
        claim(run, "seeded")
        claim(run, "seeded")
        try:
            claim(run, "uncapped")
            failures.append("claim accepted a second arm")
        except SystemExit:
            pass
    if len(PINS) != 19:
        failures.append(f"PINS holds {len(PINS)} repositories, not #665's 19")
    for failure in failures:
        print("FAIL", failure)
    if failures:
        return 1
    print("reach_arms.py self-test OK  (corpus cost, arm environment, run claim, pins)")
    return 0


def main(argv):
    if argv[1:2] == ["--self-test"]:
        return self_test()
    command, rest = argv[1], argv[2:]
    flags = {}
    positional = []
    index = 0
    while index < len(rest):
        if rest[index].startswith("--"):
            flags[rest[index]] = rest[index + 1]
            index += 2
        else:
            positional.append(rest[index])
            index += 1
    if command == "prepare":
        print("made:", " ".join(prepare(positional[0])) or "nothing")
        return 0
    if command == "funnel":
        return funnel(*positional)
    if command == "census":
        return census(positional[0], positional[1], positional[2], flags["--swift-infer"], flags["--cli"])
    if command == "cost":
        print(json.dumps(cost(positional[0]), indent=2, sort_keys=True))
        return 0
    if command == "all":
        run, arm, infer, cli, fixture = positional
        if funnel(run, arm, infer, cli) != 0:
            return 1
        out = os.path.join(run, f"census-{arm}.jsonl")
        if census(run, arm, out, flags["--swift-infer-sha"], flags["--cli-sha"]) != 0:
            return 1
        json.dump(cost(run), open(os.path.join(run, "cost.json"), "w"), indent=2, sort_keys=True)
        return subprocess.run([sys.executable, os.path.join(HERE, "predicate_outcome_reach.py"), "record",
                               out, fixture], cwd=ROOT).returncode
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
