#!/usr/bin/env bash
# Fails if README.md doesn't mention every step key defined in base.pkl.
# Catches "added a step, forgot to document it" — not prose accuracy.
set -euo pipefail

cd "$(dirname "$0")/.."

missing=()
while IFS= read -r key; do
    grep -qF "\`${key}\`" README.md || missing+=("$key")
done < <(pkl eval base.pkl -x 'allStepKeys.join("\n")')

if [ ${#missing[@]} -gt 0 ]; then
    # shellcheck disable=SC2016 # backticks are literal Markdown, not expansion
    {
        printf 'README.md is missing references to these base.pkl steps:\n'
        printf '  - `%s`\n' "${missing[@]}"
        printf 'Document them in the "What'\''s in `base.pkl`" section.\n'
    } >&2
    exit 1
fi
