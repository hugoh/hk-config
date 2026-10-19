#!/usr/bin/env bash
# Exercises scripts/migrate-v3.sh over throwaway consumer repos: what it
# rewrites, what it must leave alone, and that a second run changes nothing.
set -euo pipefail

cd "$(dirname "$0")/.."
migrate=$PWD/scripts/migrate-v3.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failed=0
fail() {
    printf 'FAIL %s: %s\n' "$case_name" "$1" >&2
    failed=1
}

# new_repo <name>: an empty git repo in $work/<name>, entered by the caller.
new_repo() {
    case_name=$1
    repo=$work/$1
    mkdir -p "$repo"
    git -C "$repo" init -q
}

# run [env...]: migrate $repo, keeping stdout/stderr in $out / $err.
run() {
    env JACTIONLINT_BIN=/nonexistent "$@" "$migrate" "$repo" >"$work/out" 2>"$work/err" || fail "script exited non-zero"
    out=$(<"$work/out")
    err=$(<"$work/err")
}

has_line() { grep -Fxq -- "$2" "$repo/$1" || fail "$1 lacks the line: $2"; }
lacks() { ! grep -Fq -- "$2" "$repo/$1" || fail "$1 still contains: $2"; }
# no_actionlint: any "actionlint" that isn't part of "jactionlint".
no_actionlint() { ! grep -Eq '(^|[^j])actionlint' "$repo/$1" || fail "$1 still mentions actionlint"; }
exists() { [ -e "$repo/$1" ] || fail "$1 is missing"; }
absent() { [ ! -e "$repo/$1" ] || fail "$1 should be gone"; }

# stub <name> <exit status> [output line]...: an executable that records its
# arguments in $work/<name>.args, prints the lines to stderr and exits.
stub() {
    local name=$1 status=$2 line
    shift 2
    {
        printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >"%s.args"\n' "$work/$name"
        for line in "$@"; do printf 'echo %q >&2\n' "$line"; done
        printf 'exit %s\n' "$status"
    } >"$work/$name"
    chmod +x "$work/$name"
}

# snapshot: hash of every file outside .git, to prove idempotence.
snapshot() { (cd "$repo" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum); }

new_repo "mise string pin"
printf '[tools]\n# keep me\nhk = "2.6.0"\nactionlint = "1.7.12"\npinact = "5.0.0"\n' >"$repo/mise.toml"
run
has_line mise.toml 'jactionlint = "2.2.0"'
has_line mise.toml 'hk = "2.6.0"'
has_line mise.toml 'pinact = "5.0.0"'
has_line mise.toml '# keep me'
no_actionlint mise.toml

new_repo "version override"
printf '[tools]\nactionlint = "1.7.12"\n' >"$repo/mise.toml"
run JACTIONLINT_VERSION=9.9.9
has_line mise.toml 'jactionlint = "9.9.9"'

new_repo "mise table pin"
printf '[tools]\nactionlint = { version = "1.7.12", os = ["linux"] }\n' >"$repo/mise.toml"
run
has_line mise.toml 'jactionlint = { version = "1.7.12", os = ["linux"] }'
case $err in *"check its version"*) ;; *) fail "no warning about the unchanged version" ;; esac

new_repo "mise quoted key"
printf '[tools]\n"actionlint" = "1.7.12"\n' >"$repo/mise.toml"
run
no_actionlint mise.toml
has_line mise.toml 'jactionlint = "2.2.0"'

new_repo "other tool names untouched"
printf '[tools]\nmyactionlint = "1.0.0"\n"aqua:foo/actionlint-wrapper" = "1.0.0"\n' >"$repo/mise.toml"
run
has_line mise.toml 'myactionlint = "1.0.0"'
has_line mise.toml '"aqua:foo/actionlint-wrapper" = "1.0.0"'

new_repo "hk.pkl overrides"
cat >"$repo/hk.pkl" <<'EOF'
local linters = new Mapping<String, Step> {
    ...Base.base
    ["actionlint"] = (Base.base["actionlint"]) {
        exclude = List("x")
    }
    ["extra"] = Builtins.actionlint
    ["pinact"] = Builtins.pinact
}
EOF
run
no_actionlint hk.pkl
has_line hk.pkl '    ["jactionlint"] = (Base.base["jactionlint"]) {'
has_line hk.pkl '    ["extra"] = Builtins.jactionlint'
has_line hk.pkl '    ["pinact"] = Builtins.pinact'

new_repo "hk.pkl step syntax"
cat >"$repo/hk.pkl" <<'EOF'
local linters = new Mapping<String, Step> {
    ["a"] = {
        check = "a"
    }
    ["b"]    =   { check = "b" }
    ["c"] {
        check = "c"
    }
    ["d"] = new Step {
        check = "d"
    }
    ["e"] = Builtins.pinact
    ["f"] = (Base.base["f"]) {
        exclude = List("x")
    }
}
EOF
run
has_line hk.pkl '    ["a"] {'
has_line hk.pkl '    ["b"] { check = "b" }'
has_line hk.pkl '    ["c"] {'
has_line hk.pkl '    ["d"] = new Step {'
has_line hk.pkl '    ["e"] = Builtins.pinact'
has_line hk.pkl '    ["f"] = (Base.base["f"]) {'

new_repo "no mise.toml or hk.pkl"
run
has_line .github/jactionlint.yaml 'profile: default'

new_repo "config: created"
run
has_line .github/jactionlint.yaml 'profile: default'

new_repo "config: tracked actionlint.yaml moves"
mkdir "$repo/.github"
printf 'self-hosted-runner:\n  labels: [x]' >"$repo/.github/actionlint.yaml" # no trailing newline
git -C "$repo" add -A
run
absent .github/actionlint.yaml
has_line .github/jactionlint.yaml 'self-hosted-runner:'
has_line .github/jactionlint.yaml '  labels: [x]'
has_line .github/jactionlint.yaml 'profile: default'
[ "$(git -C "$repo" ls-files .github/actionlint.yaml)" = "" ] || fail "old config still tracked"

new_repo "config: untracked actionlint.yml moves"
mkdir "$repo/.github"
printf 'paths: {}\n' >"$repo/.github/actionlint.yml"
run
absent .github/actionlint.yml
has_line .github/jactionlint.yaml 'paths: {}'
has_line .github/jactionlint.yaml 'profile: default'

new_repo "config: existing profile kept"
mkdir "$repo/.github"
printf 'profile: pedantic\n' >"$repo/.github/jactionlint.yaml"
run
has_line .github/jactionlint.yaml 'profile: pedantic'
lacks .github/jactionlint.yaml 'profile: default'

new_repo "config: jactionlint.yaml without profile"
mkdir "$repo/.github"
printf 'paths: {}\n' >"$repo/.github/jactionlint.yaml"
run
has_line .github/jactionlint.yaml 'paths: {}'
has_line .github/jactionlint.yaml 'profile: default'

new_repo "config: jactionlint.yaml wins over actionlint.yaml"
mkdir "$repo/.github"
printf 'profile: correctness\n' >"$repo/.github/jactionlint.yaml"
printf 'paths: {}\n' >"$repo/.github/actionlint.yaml"
run
exists .github/actionlint.yaml
has_line .github/jactionlint.yaml 'profile: correctness'

new_repo "idempotent"
mkdir "$repo/.github"
printf '[tools]\nactionlint = "1.7.12"\n' >"$repo/mise.toml"
printf '["actionlint"] = Builtins.actionlint\n["x"] = {\n}\n' >"$repo/hk.pkl"
printf 'paths: {}' >"$repo/.github/actionlint.yaml"
run
first=$(snapshot)
run
[ "$(snapshot)" = "$first" ] || fail "second run changed files"
[ "$out" = "" ] || fail "second run reported changes: $out"

# jactionlint run -----------------------------------------------------------

# lint_repo <name>: a repo with one .yml and one .yaml workflow.
lint_repo() {
    new_repo "$1"
    mkdir -p "$repo/.github/workflows"
    : >"$repo/.github/workflows/a.yml"
    : >"$repo/.github/workflows/b.yaml"
}

lint_repo "lint: clean"
stub clean 0
run JACTIONLINT_BIN="$work/clean"
case $out in *"workflows are clean"*) ;; *) fail "no clean message: $out" ;; esac
case $err in *"found issues"*) fail "guidance printed for a clean run" ;; esac
[ "$(<"$work/clean.args")" = ".github/workflows/a.yml
.github/workflows/b.yaml" ] || fail "jactionlint not given both workflow files"

lint_repo "lint: findings"
stub bad 1 \
    '.github/workflows/a.yml:4:1: workflow has no "concurrency:" [concurrency-limits]' \
    '.github/workflows/a.yml:10:3: "contents: write" is set [excessive-permissions]' \
    '.github/workflows/b.yaml:7:5: something else [some-other-rule]'
run JACTIONLINT_BIN="$work/bad"
# shellcheck disable=SC2016 # backticks are literal text in the guidance
for want in '[concurrency-limits]' 'caller-' 'cancel-in-progress: false' \
    'excessive-permissions: set `permissions: {}`' 'some-other-rule: see' \
    'jactionlint --fix' 'profile: correctness'; do
    case $err in *"$want"*) ;; *) fail "guidance lacks: $want" ;; esac
done

lint_repo "lint: only the matching rules get guidance"
stub perms 1 '.github/workflows/a.yml:10:3: "contents: write" is set [excessive-permissions]'
run JACTIONLINT_BIN="$work/perms"
case $err in *"concurrency-limits: add"*) fail "concurrency guidance for a permissions-only finding" ;; esac
case $err in *"excessive-permissions: set"*) ;; *) fail "no permissions guidance" ;; esac

lint_repo "lint: jactionlint missing"
run JACTIONLINT_BIN=/nonexistent
case $err in *"jactionlint not found"*) ;; *) fail "no missing-binary note" ;; esac

# mise_bin <dir> [jactionlint stub exit status]: a PATH dir with a fake mise
# (logging its calls to $work/mise.log) and, if given a status, a fake
# jactionlint for `mise exec`/`mise which` to find.
mise_bin() {
    mkdir -p "$1"
    # shellcheck disable=SC2016 # the fake mise expands these when it runs
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'echo "$*" >>"$MISE_LOG"' \
        'case $1 in' \
        '    install) exit "${MISE_INSTALL_STATUS:-0}" ;;' \
        '    which) command -v "$2" >/dev/null ;;' \
        '    exec) shift 2; exec "$@" ;;' \
        'esac' >"$1/mise"
    chmod +x "$1/mise"
    if [ "${2:-}" != "" ]; then
        stub "${1##*/}/jactionlint" "$2" '.github/workflows/a.yml:4:1: no concurrency [concurrency-limits]'
    fi
}
# Stubs live next to $work, and the one under bin/ must be found by name.
mise_run() { run PATH="$1:$PATH" JACTIONLINT_BIN= MISE_LOG="$work/mise.log" "${@:2}"; }

lint_repo "lint: mise installs, then lints through mise"
rm -f "$work/mise.log"
mise_bin "$work/bin-ok" 0
mise_run "$work/bin-ok"
case $out in *"workflows are clean"*) ;; *) fail "no clean message via mise: $out" ;; esac
[ "$(head -1 "$work/mise.log")" = "install" ] || fail "mise install was not run first: $(<"$work/mise.log")"
grep -Fxq 'exec -- jactionlint .github/workflows/a.yml .github/workflows/b.yaml' "$work/mise.log" || fail "jactionlint not run through mise exec: $(<"$work/mise.log")"

lint_repo "lint: mise install fails"
rm -f "$work/mise.log"
mise_bin "$work/bin-ok"
mise_run "$work/bin-ok" MISE_INSTALL_STATUS=1
case $err in *"mise install failed"*) ;; *) fail "no mise install failure note" ;; esac
grep -Fq 'exec -- jactionlint' "$work/mise.log" || fail "lint skipped after a failed mise install"

lint_repo "lint: mise has no jactionlint"
rm -f "$work/mise.log"
mise_bin "$work/bin-none"
mise_run "$work/bin-none"
case $err in *"jactionlint not found"*) ;; *) fail "no not-found note via mise" ;; esac
grep -Fq 'exec' "$work/mise.log" && fail "mise exec ran without jactionlint"

new_repo "lint: no workflows"
stub unused 1 'never called [x]'
run JACTIONLINT_BIN="$work/unused"
[ ! -e "$work/unused.args" ] || fail "jactionlint ran with no workflows"

exit "$failed"
