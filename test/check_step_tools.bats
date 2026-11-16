#!/usr/bin/env bats
# scripts/check-step-tools.sh: base.pkl's stepTools must have exactly one entry
# per step key in allStepKeys.

load helpers

setup() {
    copy_tree
}

@test "passes on the real base.pkl" {
    run "$TREE/scripts/check-step-tools.sh"
    [ "$status" -eq 0 ]
}

@test "fails and names a step that has no stepTools entry" {
    sed -i.bak '/^    \["shfmt"\] = "shfmt"$/d' "$TREE/base.pkl"
    run "$TREE/scripts/check-step-tools.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"no entry for these steps"* ]] || false
    [[ $output == *"shfmt"* ]] || false
}

@test "fails and names a stepTools entry for a step that no longer exists" {
    sed -i.bak 's/^    \["hk_pin_sync"\] = null$/&\n    ["ghost_step"] = null/' "$TREE/base.pkl"
    run "$TREE/scripts/check-step-tools.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"no longer exist"* ]] || false
    [[ $output == *"ghost_step"* ]] || false
}
