#!/usr/bin/env bash
# Runs base.pkl's hk_pin_sync command over throwaway consumer repos: it must
# pass whatever hk version is pinned (hk itself rejects a binary older than
# min_hk_version) and fail only for pins that disagree with each other.
set -euo pipefail

cd "$(dirname "$0")/.."

check=$(pkl eval base.pkl -f plain -x 'base["hk_pin_sync"].check')
min=$(pkl eval base.pkl -f plain -x min_hk_version)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pin() { printf 'package://github.com/jdx/hk/releases/download/v%s/hk@%s#/Config.pkl\n' "$1" "$1"; }

# run_case <name> <expected: pass|fail> <amends pin> <import pin> <mise pin|->
run_case() {
    local name=$1 expected=$2 amends=$3 import=$4 mise=$5 actual=pass
    rm -rf "${work:?}"/*
    {
        printf 'amends "%s"\n' "$(pin "$amends")"
        printf 'import "%s"\n' "$(pin "$import")"
    } >"$work/hk.pkl"
    [ "$mise" = "-" ] || printf '[tools]\nhk = "%s"\n' "$mise" >"$work/mise.toml"
    (cd "$work" && bash -c "$check") >/dev/null 2>&1 || actual=fail
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL %s: expected %s, got %s\n' "$name" "$expected" "$actual" >&2
        failed=1
    fi
}

failed=0
run_case "pin equals min" pass "$min" "$min" "$min"
run_case "hk ahead of min" pass 99.0.0 99.0.0 99.0.0
run_case "no mise.toml" pass "$min" "$min" -
run_case "hk behind min" pass 0.0.1 0.0.1 0.0.1
run_case "amends and import disagree" fail "$min" 99.0.0 "$min"
run_case "mise.toml differs from hk.pkl" fail 99.0.0 99.0.0 "$min"
run_case "mise.toml ahead of hk.pkl" fail "$min" "$min" 99.0.0

exit "$failed"
