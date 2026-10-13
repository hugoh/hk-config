#!/usr/bin/env bash
# Fails unless base.pkl's stepTools has exactly one entry per step key in
# allStepKeys, so a new step can't merge without declaring which mise tool
# (or none) it needs.
set -euo pipefail

cd "$(dirname "$0")/.."

all=$(pkl eval base.pkl -x 'allStepKeys.join("\n")' | sort)
declared=$(pkl eval base.pkl -x 'stepTools.keys.toList().join("\n")' | sort)

report() {
    local heading=$1 keys=$2 key
    [ "$keys" != "" ] || return 0
    printf '%s\n' "$heading" >&2
    while IFS= read -r key; do
        # shellcheck disable=SC2016 # backticks are literal Markdown, not expansion
        printf '  - `%s`\n' "$key" >&2
    done <<<"$keys"
    return 1
}

missing=$(comm -23 <(echo "$all") <(echo "$declared"))
stale=$(comm -13 <(echo "$all") <(echo "$declared"))

status=0
report 'base.pkl stepTools has no entry for these steps (use null if no pinned tool):' "$missing" || status=1
report 'base.pkl stepTools has entries for steps that no longer exist:' "$stale" || status=1
exit "$status"
