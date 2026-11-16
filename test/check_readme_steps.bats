#!/usr/bin/env bats
# scripts/check-readme-steps.sh: README.md must mention every step key that
# base.pkl defines.

load helpers

setup() {
    copy_tree
}

@test "passes on the real README" {
    run "$TREE/scripts/check-readme-steps.sh"
    [ "$status" -eq 0 ]
}

@test "fails and names a step the README no longer mentions" {
    # shellcheck disable=SC2016 # backticks are literal Markdown, not expansion
    sed -i.bak 's/`shfmt`/shfmt/g' "$TREE/README.md"
    run "$TREE/scripts/check-readme-steps.sh"
    [ "$status" -eq 1 ]
    [[ $output == *"missing references"* ]] || false
    [[ $output == *"shfmt"* ]] || false
}
