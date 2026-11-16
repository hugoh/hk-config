#!/usr/bin/env bats
# scripts/check-hk-pin-sync.sh: runs base.pkl's hk_pin_sync command over
# throwaway consumer repos; a command that stops rejecting disagreeing pins
# makes the script fail.

load helpers

setup() {
    copy_tree
}

@test "passes when the hk_pin_sync command accepts and rejects the right pins" {
    run "$TREE/scripts/check-hk-pin-sync.sh"
    [ "$status" -eq 0 ]
}

@test "fails when the command no longer rejects disagreeing pins" {
    sed -i.bak 's/check = "pins=/check = "exit 0; pins=/' "$TREE/base.pkl"
    run "$TREE/scripts/check-hk-pin-sync.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"FAIL amends and import disagree"* ]] || false
    [[ $output == *"FAIL mise.toml differs from hk.pkl"* ]] || false
}
