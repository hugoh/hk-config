# Shared by the bats suites. The checked scripts resolve everything relative
# to their own location (`cd "$(dirname "$0")/.."`), so each test works on a
# private copy of the tree and mutates that copy, never the real repo.

copy_tree() {
    TREE="${BATS_TEST_TMPDIR}/tree"
    local root="${BATS_TEST_DIRNAME}/.."
    mkdir -p "$TREE/test"
    cp -R "$root/scripts" "$root/presets" "$TREE/"
    cp -R "$root/test/fixtures" "$TREE/test/"
    cp "$root/base.pkl" "$root/hk.pkl" "$root/mise.toml" "$root/README.md" "$root/renovate.json" "$TREE/"
}
