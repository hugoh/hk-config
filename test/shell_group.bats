#!/usr/bin/env bats
# shellcheck disable=SC2016
# End-to-end checks for base.pkl's `shell` group. Each test builds a throwaway
# git repo whose hk.pkl spreads the local base.pkl and runs the real hk, so a
# regression in what the group lints fails here. The notable case is *.bats,
# which hk's builtin step for shellcheck does not match on its own.

bats_require_minimum_version 1.5.0

setup() {
    REPO="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "$REPO"
    cp "${BATS_TEST_DIRNAME}/../base.pkl" "$REPO/"
    local hk_version
    hk_version=$(hk --version | awk '{print $2}')
    cat >"$REPO/hk.pkl" <<PKL
amends "package://github.com/jdx/hk/releases/download/v${hk_version}/hk@${hk_version}#/Config.pkl"
import "base.pkl" as Base

min_hk_version = Base.min_hk_version

local linters = new Mapping<String, Step> {
    ...Base.shell
}

steps = linters
PKL
    git -C "$REPO" init -q
}

lint() { # lint <step>: run one hk step over every file in the repo
    git -C "$REPO" add -A
    cd "$REPO" && hk check --all --step "$1" 2>&1
}

@test "the shell group is exactly shellcheck, shellharden and shfmt" {
    run pkl eval "${BATS_TEST_DIRNAME}/../base.pkl" -x 'shell.keys.toList().sort().join(",")'
    [ "$status" -eq 0 ]
    [ "$output" = "shellcheck,shellharden,shfmt" ]
}

@test "shellcheck flags a bats-specific trap in a .bats file" {
    printf '#!/usr/bin/env bats\n\n@test "x" {\n    ! false\n    true\n}\n' >"$REPO/bad.bats"
    run lint shellcheck
    [ "$status" -ne 0 ]
    [[ $output == *SC2314* ]] || false
}

@test "shellcheck passes a clean .bats file" {
    printf '#!/usr/bin/env bats\n\n@test "x" {\n    run true\n    [ "$status" -eq 0 ]\n}\n' >"$REPO/good.bats"
    run lint shellcheck
    [ "$status" -eq 0 ]
}

@test "shellcheck still checks plain .sh files" {
    printf '#!/usr/bin/env bash\necho $1\n' >"$REPO/bad.sh"
    run lint shellcheck
    [ "$status" -ne 0 ]
    [[ $output == *SC2086* ]] || false
}

@test "shfmt flags an unformatted .bats file" {
    printf '#!/usr/bin/env bats\n\n@test "x" {\nif true;then\necho hi\nfi\n}\n' >"$REPO/messy.bats"
    run lint shfmt
    [ "$status" -ne 0 ]
}

@test "shfmt passes a formatted .bats file" {
    printf '#!/usr/bin/env bats\n\n@test "x" {\nif true;then\necho hi\nfi\n}\n' >"$REPO/messy.bats"
    shfmt -w "$REPO/messy.bats"
    run lint shfmt
    [ "$status" -eq 0 ]
}
