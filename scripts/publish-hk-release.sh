#!/usr/bin/env bash
# Publishes an hk-vX.Y.Z release naming the hk version the newest hk-config
# release was built against. presets/hk-pins.json offers consuming repos only
# those versions.
set -euo pipefail

tag=$(git tag --list 'v[0-9]*' --sort=-v:refname | sed -n 1p)
hk=$(git show "${tag}:base.pkl" | sed -n 's/^min_hk_version = "\(.*\)"/\1/p')
if [ "$hk" = "" ]; then
    echo "no min_hk_version in ${tag}:base.pkl" >&2
    exit 1
fi

if gh release view "hk-v${hk}" >/dev/null 2>&1; then
    exit 0
fi
gh release create "hk-v${hk}" --target "$(git rev-list -n 1 "$tag")" --latest=false \
    --title "hk-v${hk}" \
    --notes "hk ${hk} is supported as of hk-config ${tag}. Renovate reads this release; there is nothing to download."
