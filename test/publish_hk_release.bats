#!/usr/bin/env bats
# scripts/publish-hk-release.sh: advertises, as an hk-vX.Y.Z release, the hk
# version the newest hk-config release was built against.

bats_require_minimum_version 1.5.0

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../scripts/publish-hk-release.sh"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
    export GH_LOG="${BATS_TEST_TMPDIR}/gh.log" GH_VIEW_STATUS=1
    mkdir "${BATS_TEST_TMPDIR}/bin" "${BATS_TEST_TMPDIR}/repo"
    cat >"${BATS_TEST_TMPDIR}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
[ "$2" != view ] || exit "$GH_VIEW_STATUS"
FAKE
    chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
    export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    git init -q
}

commit_hk() {
    printf 'min_hk_version = "%s"\n' "$1" >base.pkl
    git add base.pkl
    git commit -qm "hk $1"
}

@test "creates a release for the hk version of the newest v tag, not of HEAD" {
    commit_hk 2.9.0
    git tag v3.9.0
    commit_hk 2.12.0
    git tag v3.10.0
    commit_hk 2.99.0

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q "^release create hk-v2.12.0 --target $(git rev-parse v3.10.0) --latest=false " "$GH_LOG"
}

@test "does nothing when the hk release already exists" {
    commit_hk 2.12.0
    git tag v3.10.0
    export GH_VIEW_STATUS=0

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    run ! grep -q "release create" "$GH_LOG"
}

@test "fails when the released base.pkl has no hk version" {
    echo "// nothing" >base.pkl
    git add base.pkl
    git commit -qm empty
    git tag v1.0.0

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [ ! -e "$GH_LOG" ]
}
