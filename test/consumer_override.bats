#!/usr/bin/env bats
# A consumer-shaped hk.pkl that overrides shared steps must still load. An hk
# upgrade can change what Pkl accepts without breaking this repo's own hk.pkl.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    CONSUMER="${BATS_TEST_TMPDIR}/consumer"
    mkdir "$CONSUMER"
    cp "$ROOT/base.pkl" "$CONSUMER/"
    HK_VERSION="$(sed -n 's/^min_hk_version = "\(.*\)"/\1/p' "$ROOT/base.pkl")"
    HK="package://github.com/jdx/hk/releases/download/v${HK_VERSION}/hk@${HK_VERSION}#"
}

write_consumer() {
    cat >"$CONSUMER/hk.pkl" <<PKL
amends "$HK/Config.pkl"
import "$HK/Builtins.pkl"
import "base.pkl" as Base

min_hk_version = Base.min_hk_version

$1

steps = linters
PKL
}

validate() {
    cd "$CONSUMER" && mise -C "$ROOT" exec -- sh -c "cd '$CONSUMER' && hk validate"
}

@test "spreading the shared groups, then amending them, loads" {
    write_consumer 'local common = new Mapping<String, Step> {
    ...Base.base
    ...Base.python
}

local linters = (common) {
    ["ty"] = (Builtins.ty) { check = "true" }
}'

    run validate

    [ "$status" -eq 0 ]
}

@test "overriding a spread key in the same block is rejected" {
    write_consumer 'local linters = new Mapping<String, Step> {
    ...Base.python
    ["ty"] = (Builtins.ty) { check = "true" }
}'

    run validate

    [ "$status" -ne 0 ]
    [[ $output == *"Duplicate definition"* ]] || false
}
