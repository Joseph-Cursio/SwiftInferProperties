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
    reach_arms.py rerun   <run-dir> <arm> <repo> <swift-infer> <cli> <fixture.jsonl> --swift-infer-sha <sha> --cli-sha <sha>
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

# §3, recorded 2026-11-12 before any lever code. #665's 19, in its order. SwiftFormatRuleStudio moved from
# `5cea6a7` to `61cfea1` (its tokenizer fix, #26) by amendment A5, in every arm, through `rerun`.
PINS = {
    "SwiftMarkdownWiki": "51b789e", "SwiftProjectLint": "6a231cda", "SwiftAssist": "8e1bc8d",
    "SwiftPropertyLaws": "b45d1bf", "SwiftUMLStudio": "9ad7631", "SwiftLintRuleStudio": "77cc792",
    "pbt-workbook-corpus": "6df2650", "pbt-book": "3e76194", "SwiftFormatRuleStudio": "61cfea1",
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


def census_command(run, arm, out, swift_infer, cli, repos=PINS):
    """The repositories go before the options: `run`'s `rest` is one positional, and argparse stops
    filling it at the first option, so a repository list after `--cli` is rejected outright — which is
    how the first A0–A2 runs lost their census step (2026-11-12)."""
    return [sys.executable, os.path.join(HERE, "predicate_outcome_reach.py"), "run", run, out, *repos,
            "--arm", arm, "--swift-infer", swift_infer, "--cli", cli]


def census(run, arm, out, swift_infer, cli, repos=PINS):
    claim(run, arm)
    command = census_command(run, arm, out, swift_infer, cli, repos)
    with open(os.path.join(run, "census.log"), "a", encoding="utf-8") as log:
        return subprocess.run(command, cwd=ROOT, env=arm_environment(arm), stdout=log,
                              stderr=subprocess.STDOUT).returncode


def repo_files(run, repo):
    """What the funnel writes for one repository in a run directory, its tree aside."""
    names = {f"result-{repo}.json", f"{repo}-seeds.json", f"aside-{repo}"}
    prefixes = (f"discover-{repo}-", f"index-{repo}-")
    return sorted(os.path.join(run, name) for name in os.listdir(run)
                  if name in names or (name.startswith(prefixes) and _target_suffix(name, repo)))


def _target_suffix(name, repo):
    """`discover-<repo>-<target>.txt`: true only when the text after the prefix holds no other repository's
    name as a longer prefix — `pbt-workbook` must not take `pbt-workbook-grader`'s files."""
    rest = name.split("-", 1)[1]
    return not any(other != repo and other.startswith(repo + "-") and rest.startswith(other + "-")
                   for other in PINS)


def reset_repo(run, repo, siblings=SIBLINGS):
    """Removes one repository's tree and funnel output from a run, so the funnel walks it again at its
    current pin. The other repositories' results stay, and the funnel skips them."""
    import shutil
    tree = tree_path(run, repo)
    if os.path.isdir(tree):
        subprocess.run(["git", "-C", os.path.join(siblings, repo), "worktree", "remove", "--force", tree],
                       check=True, capture_output=True)
    for path in repo_files(run, repo):
        shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)


def drop_repo_rows(path, repo):
    """Rewrites a census file without `repo`'s rows; the census then probes that repository again and
    appends, since it skips only the packages it finds in the file. Returns how many rows went."""
    if not os.path.exists(path):
        return 0
    lines = [line for line in open(path, encoding="utf-8") if line.strip()]
    kept = [line for line in lines if json.loads(line).get("repo") != repo]
    with open(path, "w", encoding="utf-8") as handle:
        handle.writelines(kept)
    return len(lines) - len(kept)


def record(out, fixture):
    return subprocess.run([sys.executable, os.path.join(HERE, "predicate_outcome_reach.py"), "record",
                           out, fixture], cwd=ROOT).returncode


def rerun(run, arm, repo, infer, cli, swift_infer_sha, cli_sha, fixture):
    """One repository again in a finished arm, at its current pin (amendment A5): funnel, census, cost
    and fixture, every other repository's rows untouched."""
    claim(run, arm)
    reset_repo(run, repo)
    if funnel(run, arm, infer, cli) != 0:
        return 1
    out = os.path.join(run, f"census-{arm}.jsonl")
    print(f"{repo}: {drop_repo_rows(out, repo)} census rows dropped from {out}", flush=True)
    if census(run, arm, out, swift_infer_sha, cli_sha, repos=[repo]) != 0:
        return 1
    json.dump(cost(run), open(os.path.join(run, "cost.json"), "w"), indent=2, sort_keys=True)
    return record(out, fixture)


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
    with tempfile.TemporaryDirectory() as run:
        names = ["result-pbt-workbook.json", "result-pbt-workbook-grader.json", "pbt-workbook-seeds.json",
                 "discover-pbt-workbook-WorkbookRunner.txt", "discover-pbt-workbook-grader-WorkbookGraderCore.txt",
                 "index-pbt-workbook-WorkbookExercises.json", "index-pbt-workbook-sampler-WorkbookCorpus.json",
                 "result-SwiftLintRuleStudioTeam.json", "census-seeded.jsonl"]
        for name in names:
            open(os.path.join(run, name), "w").close()
        os.makedirs(os.path.join(run, "aside-pbt-workbook"))
        os.makedirs(os.path.join(run, "aside-pbt-workbook-grader"))
        picked = [os.path.basename(path) for path in repo_files(run, "pbt-workbook")]
        expected = ["aside-pbt-workbook", "discover-pbt-workbook-WorkbookRunner.txt",
                    "index-pbt-workbook-WorkbookExercises.json", "pbt-workbook-seeds.json", "result-pbt-workbook.json"]
        if picked != expected:
            failures.append(f"repo_files takes another repository's files: {picked}")
        if repo_files(run, "SwiftLintRuleStudio"):
            failures.append("repo_files takes SwiftLintRuleStudioTeam's result for SwiftLintRuleStudio")
        census_file = os.path.join(run, "census-seeded.jsonl")
        with open(census_file, "w") as handle:
            handle.write('{"repo": "A", "n": 1}\n{"repo": "B", "n": 2}\n\n{"repo": "A", "n": 3}\n')
        if drop_repo_rows(census_file, "A") != 2 or open(census_file).read() != '{"repo": "B", "n": 2}\n':
            failures.append(f"drop_repo_rows left {open(census_file).read()!r}")
    sys.path.insert(0, HERE)
    import predicate_outcome_reach
    one = census_command("/r", "seeded", "/o.jsonl", "abc", "def", repos=["SwiftFormatRuleStudio"])
    _, parsed_one = predicate_outcome_reach.parse_arguments(one[1:])
    if parsed_one.rest != ["/r", "/o.jsonl", "SwiftFormatRuleStudio"]:
        failures.append(f"a one-repository census parses as {parsed_one.rest}")
    built = census_command("/r", "seeded", "/o.jsonl", "abc", "def")
    try:
        _, parsed = predicate_outcome_reach.parse_arguments(built[1:])
        if parsed.rest != ["/r", "/o.jsonl", *PINS] or parsed.arm != "seeded" or parsed.cli != "def":
            failures.append(f"census_command parses as {parsed}")
    except SystemExit:
        failures.append("predicate_outcome_reach.py rejects the command census builds")
    for failure in failures:
        print("FAIL", failure)
    if failures:
        return 1
    print("reach_arms.py self-test OK  (corpus cost, arm environment, run claim, pins, census command parses, rerun file selection and row drop)")
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
        return record(out, fixture)
    if command == "rerun":
        run, arm, repo, infer, cli, fixture = positional
        if repo not in PINS:
            raise SystemExit(f"{repo} is not a pinned repository")
        return rerun(run, arm, repo, infer, cli, flags["--swift-infer-sha"], flags["--cli-sha"], fixture)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
