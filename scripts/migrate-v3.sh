#!/usr/bin/env -S zsh -f
# Migrates a consumer repo from hk-config v2 (actionlint) to v3 (jactionlint):
#   - mise.toml: renames the `actionlint` tool to `jactionlint`
#   - hk.pkl: renames `actionlint` step overrides / Builtins references, and
#     rewrites `["key"] = {` steps to `["key"] {` (hk 2.6.0 rejects the former)
#   - .github/jactionlint.yaml: carries over actionlint's config if there is
#     one, and makes sure it sets `profile: default`
# It doesn't touch the hk / hk-config pins; Renovate (or you) bumps those.
# Idempotent: running it again on a migrated repo changes nothing.
# Then it runs `hk check --all` and exits with its status.
#
# Usage: scripts/migrate-v3.sh [repo-dir]    (default: current directory)
# Env:   JACTIONLINT_VERSION  version written to mise.toml (default below)
#        JACTIONLINT_BIN      jactionlint binary to lint with (skips mise)
#        HK_BIN               hk binary for the final check (skips mise)
set -euo pipefail

version=${JACTIONLINT_VERSION:-2.2.0}
cd "${1:-.}"

# sedi <sed -E args> <file>: in-place edit that works with GNU and BSD sed.
sedi() { sed -E -i.bak "$@" && rm -f -- "${@[-1]}.bak"; }

# mise.toml: `actionlint = "1.7.12"` -> `jactionlint = "<version>"`. Other
# spellings (table form, backend prefixes) only get the key renamed.
if [ -f mise.toml ]; then
    if grep -Eq '^"?actionlint"?[[:space:]]*=[[:space:]]*"' mise.toml; then
        sedi "s/^\"?actionlint\"?[[:space:]]*=[[:space:]]*\"[^\"]*\"/jactionlint = \"$version\"/" mise.toml
        echo "mise.toml: actionlint -> jactionlint $version"
    elif grep -Eq '^"?actionlint"?[[:space:]]*=' mise.toml; then
        sedi 's/^"?actionlint"?([[:space:]]*=)/jactionlint\1/' mise.toml
        echo "mise.toml: renamed the actionlint key; check its version by hand" >&2
    fi
fi

# hk.pkl: step overrides (`["actionlint"]`, `Base.base["actionlint"]`) and
# `Builtins.actionlint`.
if [ -f hk.pkl ] && grep -Eq '\["actionlint"\]|Builtins\.actionlint' hk.pkl; then
    sedi 's/\["actionlint"\]/["jactionlint"]/g; s/Builtins\.actionlint/Builtins.jactionlint/g' hk.pkl
    echo "hk.pkl: renamed actionlint -> jactionlint"
fi

# latest_version <repo-url> <version regex>: the highest tag of the repo whose
# version (the tag without its leading v) matches the regex, or nothing.
latest_version() {
    git ls-remote --tags --refs "$1" 2>/dev/null |
        sed -E 's#.*refs/tags/v?##' | grep -E "$2" | sort -V | tail -1 || true
}

# hk: bump the hk pins (hk.pkl amends/import URLs, a literal min_hk_version,
# and mise.toml's `hk =`) together, since hk_pin_sync wants them to agree and
# v3 needs hk >= 2.7.0. HK_VERSION pins a version; otherwise it's the latest
# stable hk release, and a pin that is already newer is left alone.
hk_version=${HK_VERSION:-}
hk_explicit=$hk_version
if [ "$hk_version" = "" ]; then
    hk_version=$(latest_version https://github.com/jdx/hk '^[0-9]+\.[0-9]+\.[0-9]+$')
fi
if [ "$hk_version" = "" ]; then
    echo "could not determine the latest hk release; set HK_VERSION to bump the hk pins" >&2
else
    hk_pins=$(grep -Eo 'jdx/hk/releases/download/v[^/]+/hk@[^#]+#' hk.pkl 2>/dev/null || true)
    hk_current=$(sed -n 's#^hk[[:space:]]*=[[:space:]]*"\([^"]*\)".*#\1#p' mise.toml 2>/dev/null | head -1 || true)
    [ "$hk_current" != "" ] || hk_current=$(printf '%s\n' "$hk_pins" | sed -E 's|.*hk@||; s|#$||' | sort -V | tail -1)
    newest=$(printf '%s\n%s\n' "$hk_current" "$hk_version" | sort -V | tail -1)
    if [ "$hk_explicit" = "" ] && [ "$hk_current" != "" ] && [ "$newest" != "$hk_version" ]; then
        echo "hk: $hk_current is newer than the latest release $hk_version; leaving it"
    else
        wanted="jdx/hk/releases/download/v$hk_version/hk@$hk_version#"
        if [ -f hk.pkl ]; then
            if printf '%s\n' "$hk_pins" | grep -Fvx -- "$wanted" | grep -q .; then
                sedi "s|(jdx/hk/releases/download/)v[^/]+(/hk@)[^#]+#|\\1v$hk_version\\2$hk_version#|g" hk.pkl
                echo "hk.pkl: hk -> $hk_version"
            fi
            if grep -Eq 'min_hk_version[[:space:]]*=[[:space:]]*"' hk.pkl &&
                ! grep -Eq "min_hk_version[[:space:]]*=[[:space:]]*\"$hk_version\"" hk.pkl; then
                sedi "s|(min_hk_version[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\\1\"$hk_version\"|" hk.pkl
                echo "hk.pkl: min_hk_version -> $hk_version"
            fi
        fi
        if grep -Eq '^hk[[:space:]]*=' mise.toml 2>/dev/null &&
            ! grep -Eq "^hk[[:space:]]*=[[:space:]]*\"$hk_version\"[[:space:]]*\$" mise.toml; then
            sedi "s|^(hk[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\\1\"$hk_version\"|" mise.toml
            echo "mise.toml: hk -> $hk_version"
        fi
    fi
fi

# hk-config: point the hk-config import in hk.pkl at the latest v3 release
# (HK_CONFIG_VERSION pins one). The v2 definitions still have the actionlint
# step, so this is what makes the renames above resolve.
if [ -f hk.pkl ] && grep -q 'hugoh/hk-config/releases/download/' hk.pkl; then
    config_version=${HK_CONFIG_VERSION:-}
    if [ "$config_version" = "" ]; then
        config_version=$(latest_version https://github.com/hugoh/hk-config '^3\.[0-9]+\.[0-9]+$')
    fi
    if [ "$config_version" = "" ]; then
        echo "could not find a v3 hk-config release; set HK_CONFIG_VERSION, or bump the hk-config pin in hk.pkl once v3 is released" >&2
    else
        wanted="hugoh/hk-config/releases/download/v$config_version/hk-config@$config_version#"
        if grep -Eo 'hugoh/hk-config/releases/download/v[^/]+/hk-config@[^#]+#' hk.pkl | grep -Fvx -- "$wanted" | grep -q .; then
            sedi "s|(hugoh/hk-config/releases/download/)v[^/]+(/hk-config@)[^#]+#|\\1v$config_version\\2$config_version#|g" hk.pkl
            echo "hk.pkl: hk-config -> $config_version"
        fi
    fi
fi

# hk.pkl: hk 2.6.0 rejects `["key"] = { ... }` (no `new Step`); the amending
# form `["key"] { ... }` means the same and works in every hk version.
if [ -f hk.pkl ] && grep -Eq '^[[:space:]]*\[[^]]+\][[:space:]]*=[[:space:]]*\{' hk.pkl; then
    sedi 's/^([[:space:]]*\[[^]]+\])[[:space:]]*=[[:space:]]*\{/\1 {/' hk.pkl
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
# clean before can have findings now. This only reports and says what to do
# about them; the hk check below is what decides the exit status.
lint_workflows() {
setopt null_glob
workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
[ "${#workflows[@]}" -gt 0 ] || return 0

# Install the tools mise.toml now pins (jactionlint, via the rename above) and
# run through mise so that pin is the version used. JACTIONLINT_BIN skips mise
# and runs that binary as is.
if [ "${JACTIONLINT_BIN:-}" != "" ]; then
    lint=("$JACTIONLINT_BIN")
    have=(command -v "$JACTIONLINT_BIN")
elif command -v mise >/dev/null 2>&1; then
    mise install >&2 || echo "mise install failed; linting with what is installed" >&2
    lint=(mise exec -- jactionlint)
    have=(mise which jactionlint)
else
    lint=(jactionlint)
    have=(command -v jactionlint)
fi
if ! "${have[@]}" >/dev/null 2>&1; then
    echo "jactionlint not found; install it ('mise install') and run 'jactionlint' to check the workflows" >&2
    return 0
fi
if findings=$("${lint[@]}" "${workflows[@]}" 2>&1); then
    echo "jactionlint: workflows are clean"
    return 0
fi
printf '%s\n' "$findings" >&2
rules=(${(f)"$(printf '%s\n' "$findings" | grep -Eo '\[[a-z0-9-]+\]$' | tr -d '[]' | sort -u || true)"})
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
}

lint_workflows

# The migrated repo must pass its own checks. HK_BIN skips mise and runs that
# binary as is. Repos without an hk.pkl have nothing to check.
[ -f hk.pkl ] || exit 0
if [ "${HK_BIN:-}" != "" ]; then
    hk_cmd=("$HK_BIN")
elif command -v mise >/dev/null 2>&1; then
    hk_cmd=(mise exec -- hk)
else
    hk_cmd=(hk)
fi
"${hk_cmd[@]}" check --all
