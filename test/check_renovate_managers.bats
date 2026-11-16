#!/usr/bin/env bats
# scripts/check-renovate-managers.mjs: the custom managers in
# presets/hk-pins.json must still extract the hk and hk-config pins.

load helpers

setup() {
    copy_tree
    # The script finds renovate via `mise where` in the current directory, so
    # run from the real repo (its mise.toml pins renovate); the script still
    # reads the mutated tree because it resolves paths from its own location.
    cd "${BATS_TEST_DIRNAME}/.." || return 1
}

@test "passes on the real preset" {
    run node "$TREE/scripts/check-renovate-managers.mjs"
    [ "$status" -eq 0 ]
    [[ $output != *FAIL* ]] || false
}

@test "fails when a manager regex stops matching the pin URL" {
    sed -i.bak 's#hk-config/releases/download#hk-config/releases/downloadz#' "$TREE/presets/hk-pins.json"
    run node "$TREE/scripts/check-renovate-managers.mjs"
    [ "$status" -eq 1 ]
    [[ $output == *FAIL* ]] || false
}
