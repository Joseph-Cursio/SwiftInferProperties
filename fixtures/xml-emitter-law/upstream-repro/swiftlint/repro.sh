#!/bin/sh
# Reproduces realm/SwiftLint's XML reporters writing malformed XML. Needs `swiftlint` and `xmllint` on PATH.
# Usage: repro.sh [WORKDIR]
set -u
W=${1:-$(mktemp -d)}
mkdir -p "$W/esc" "$W/combining" "$W/custom"

# 1. Default rules only: a TODO comment holding a pasted ANSI escape (U+001B). swiftc accepts it in a comment.
printf '// TODO: \033[1mbold\033[0m later\nlet y = 2\n' > "$W/esc/Todo.swift"
: > "$W/esc/.swiftlint.yml"
# 2. Default rules only: a TODO comment holding '<' followed by U+0301 COMBINING ACUTE ACCENT (UTF-8 CC 81).
printf '// TODO: use a <\314\201 b\nlet y = 2\n' > "$W/combining/Todo.swift"
: > "$W/combining/.swiftlint.yml"
# 3. A custom rule whose key holds '<'. GitLabJUnitReporter writes the rule identifier unescaped.
printf 'print("x")\n' > "$W/custom/Print.swift"
cat > "$W/custom/.swiftlint.yml" <<'YAML'
only_rules:
  - custom_rules
custom_rules:
  "a<b":
    regex: 'print\('
    message: "Avoid print"
YAML

swiftlint version
for case in esc combining; do swiftc -typecheck "$W/$case/Todo.swift" && echo "$case/Todo.swift type-checks"; done
for case in esc combining custom; do
    for reporter in checkstyle junit gitlab; do
        [ "$case" = custom ] && [ "$reporter" != gitlab ] && continue
        out="$W/$case-$reporter.xml"
        (cd "$W/$case" && swiftlint lint --quiet --reporter $reporter > "$out")
        echo "== $case, --reporter $reporter"
        cat -v "$out" | grep -E '\^\[|<M-|a<b' | head -2 | sed 's/^[[:space:]]*/  /'
        xmllint --noout "$out" 2>&1 | head -1 | sed "s|$W/||"
    done
done
