#!/usr/bin/env bash
# Migrates a consumer repo from hk-config v2 (actionlint) to v3 (jactionlint):
#   - mise.toml: renames the `actionlint` tool to `jactionlint`
#   - hk.pkl: renames `actionlint` step overrides / Builtins references, and
#     rewrites `["key"] = {` steps to `["key"] {` (hk 2.6.0 rejects the former)
#   - .github/jactionlint.yaml: carries over actionlint's config if there is
#     one, and makes sure it sets `profile: default`
# It doesn't touch the hk / hk-config pins; Renovate (or you) bumps those.
# Idempotent: running it again on a migrated repo changes nothing.
#
# Usage: scripts/migrate-v3.sh [repo-dir]    (default: current directory)
# Env:   JACTIONLINT_VERSION  version written to mise.toml (default below)
set -euo pipefail

version=${JACTIONLINT_VERSION:-2.2.0}
cd "${1:-.}"

# mise.toml: `actionlint = "1.7.12"` -> `jactionlint = "<version>"`. Other
# spellings (table form, backend prefixes) only get the key renamed.
if [ -f mise.toml ]; then
    if grep -Eq '^"?actionlint"?[[:space:]]*=[[:space:]]*"' mise.toml; then
        sed -E -i "s/^\"?actionlint\"?[[:space:]]*=[[:space:]]*\"[^\"]*\"/jactionlint = \"$version\"/" mise.toml
        echo "mise.toml: actionlint -> jactionlint $version"
    elif grep -Eq '^"?actionlint"?[[:space:]]*=' mise.toml; then
        sed -E -i 's/^"?actionlint"?([[:space:]]*=)/jactionlint\1/' mise.toml
        echo "mise.toml: renamed the actionlint key; check its version by hand" >&2
    fi
fi

# hk.pkl: step overrides (`["actionlint"]`, `Base.base["actionlint"]`) and
# `Builtins.actionlint`.
if [ -f hk.pkl ] && grep -Eq '\["actionlint"\]|Builtins\.actionlint' hk.pkl; then
    sed -E -i 's/\["actionlint"\]/["jactionlint"]/g; s/Builtins\.actionlint/Builtins.jactionlint/g' hk.pkl
    echo "hk.pkl: renamed actionlint -> jactionlint"
fi

# hk.pkl: hk 2.6.0 rejects `["key"] = { ... }` (no `new Step`); the amending
# form `["key"] { ... }` means the same and works in every hk version.
if [ -f hk.pkl ] && grep -Eq '^[[:space:]]*\[[^]]+\][[:space:]]*=[[:space:]]*\{' hk.pkl; then
    sed -E -i 's/^([[:space:]]*\[[^]]+\])[[:space:]]*=[[:space:]]*\{/\1 {/' hk.pkl
    echo 'hk.pkl: rewrote ["key"] = { to ["key"] {'
fi

# jactionlint reads actionlint's config, but looks for its own file first.
config=.github/jactionlint.yaml
if [ ! -f "$config" ]; then
    for old in .github/actionlint.yaml .github/actionlint.yml; do
        if [ -f "$old" ]; then
            if git ls-files --error-unmatch "$old" >/dev/null 2>&1; then
                git mv "$old" "$config"
            else
                mv "$old" "$config"
            fi
            echo "$old -> $config"
            break
        fi
    done
fi
mkdir -p .github
if [ ! -f "$config" ]; then
    echo 'profile: default' >"$config"
    echo "$config: created with profile: default"
elif ! grep -Eq '^profile:' "$config"; then
    # Keep a missing trailing newline from gluing the key onto the last line.
    [ "$(tail -c1 "$config")" = "" ] || echo >>"$config"
    echo 'profile: default' >>"$config"
    echo "$config: added profile: default"
fi

# Lint the workflows with the profile just configured. The default profile
# adds security and policy rules that actionlint never had, so a repo that was
# clean before can have findings now. They don't undo the migration, so this
# only reports (exit status stays 0) and says what to do about them.
lint=${JACTIONLINT_BIN:-jactionlint}
shopt -s nullglob
workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
[ "${#workflows[@]}" -gt 0 ] || exit 0
if ! command -v "$lint" >/dev/null 2>&1; then
    echo "jactionlint not found; run 'mise install' and then 'jactionlint' to check the workflows" >&2
    exit 0
fi
if findings=$("$lint" "${workflows[@]}" 2>&1); then
    echo "jactionlint: workflows are clean"
    exit 0
fi
printf '%s\n' "$findings" >&2
mapfile -t rules < <(printf '%s\n' "$findings" | grep -Eo '\[[a-z0-9-]+\]$' | tr -d '[]' | sort -u)
{
    echo
    echo "jactionlint found issues in the workflows (profile: default). To fix them:"
    for rule in "${rules[@]}"; do
        case $rule in
            concurrency-limits)
                cat <<'TIP'
  - concurrency-limits: add a top-level `concurrency:` block. If the jobs call
    reusable workflows, make the group caller-specific, or the called workflow
    cancels itself (inside it, github.workflow is the caller's name):
        concurrency:
          group: ${{ github.workflow }}-caller-${{ github.event.pull_request.number || github.ref }}
          cancel-in-progress: true
    For release/publish workflows (and any push-to-main one) use
    `group: ${{ github.workflow }}-caller-${{ github.ref }}` and
    `cancel-in-progress: false`: cancelling a release half-way is worse than
    queueing.
TIP
                ;;
            excessive-permissions)
                cat <<'TIP'
  - excessive-permissions: set `permissions: {}` at the workflow level and
    move the write scopes (e.g. `contents: write`) onto the job that needs
    them, so a job added later doesn't inherit them silently.
TIP
                ;;
            *)
                echo "  - $rule: see 'jactionlint --list-rules' and the rule's docs for the fix"
                ;;
        esac
    done
    cat <<'TIP'

Other options:
  - 'jactionlint --fix' applies the safe fixes ('--diff' previews them).
  - Findings that can't be fixed yet: '# jactionlint ignore=<rule>' on the
    line, or a baseline ('jactionlint --baseline-write') to fail only on new ones.
  - To start from actionlint-equivalent checks, set 'profile: correctness' in
    .github/jactionlint.yaml and move up to 'default' once the workflows are clean.
TIP
} >&2
