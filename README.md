# hk-config

Shared [`hk`](https://hk.jdx.dev/) building blocks for hugoh's repos, published
as a [Pkl package](https://pkl-lang.org/main/current/language-reference/index.html#packages)
via GitHub Releases — no central package registry involved, the release
assets themselves are the package.

## Usage

```pkl
amends "package://github.com/jdx/hk/releases/download/vX.Y.Z/hk@X.Y.Z#/Config.pkl"
import "package://github.com/jdx/hk/releases/download/vX.Y.Z/hk@X.Y.Z#/Builtins.pkl"
import "package://github.com/hugoh/hk-config/releases/download/vA.B.C/hk-config@A.B.C#/base.pkl" as Base

min_hk_version = Base.min_hk_version

local linters = new Mapping<String, Step> {
    ...Base.base
    // repo-specific overrides and additions go here, same as before
    ["trailing_whitespace"] = (Builtins.trailing_whitespace) {
        exclude = List("some/generated/dir/**")
    }
}
```

`X.Y.Z` is the [hk release](https://github.com/jdx/hk/releases) you're pinning
to, and `A.B.C` is the
[hk-config release](https://github.com/hugoh/hk-config/releases) you're
pinning to — check the latest tags rather than hardcoding an example version
here, since these drift over time and Renovate keeps consuming repos' actual
pins current (see `renovate.json` below).

Repos with no local overrides can spread `Base.base` straight into their
`linters` mapping with nothing else. Repos that already exclude paths,
swap a command, or add extra steps keep doing that exactly as they do
today — only the boilerplate step _definitions_ move here, the per-repo
customization stays local.

This repo's own `hk.pkl` does the same thing, importing `base.pkl` locally
(`import "base.pkl"`, not the package URL — no bootstrapping problem, since
it's just reading a sibling file off disk).

## What's in `base.pkl`

The lowest-common-denominator step set found active, unmodified, across every
hugoh repo's `hk.pkl` `Common` group: `actionlint`, `pinact`,
`check_merge_conflict`, `trailing_whitespace`, `mixed_line_ending`,
`newlines`, `check_case_conflict`, `check_added_large_files`,
`check_executables_have_shebangs`, `check_symlinks`, `gitleaks`,
`ghalint_workflow`, `rumdl`, `rumdl_format`, `biome`, `zizmor`, `typos`,
`mise`, `tombi`, `tombi_format`, `ryl`. Keys match the `Builtins` identifier
they map to, so the step name always tells you which builtin is running.

`biome` covers JSON as well as JS/TS/JSX — that's why `dprint` (previously
the only JSON formatter in the shared set) was dropped: dprint's `json` and
`biome` plugins were doing overlapping, redundant work on the same files, and
a native binary (biome) is lighter than dprint's WASM plugin pipeline. Repos
that still need markdown/toml/yaml/JSON formatting beyond what
rumdl/tombi/ryl/biome already lint get that from those dedicated steps now,
not from a separate dprint config.

More group files (e.g. per-language extras) may be added alongside it later —
`base.pkl` is named for being the foundation those would build on top of, not
because it's the only file this package will ever contain.

## `min_hk_version`

`base.pkl` exports `min_hk_version`, set to the same version as the
`amends`/`import` pins above it. hk's `Config.pkl` schema enforces this at
runtime — if the installed `hk` binary is older, `hk` panics with a clear
"version X is less than the minimum required version Y" error instead of
failing in some more confusing way. Because Pkl `amends` targets must be
static, consuming repos need one extra line to actually apply it:
`min_hk_version = Base.min_hk_version` in their own `hk.pkl` (shown above) —
importing `base.pkl` alone doesn't merge its properties into the amending
module.

## Renovate

`renovate.json` (in this repo) is where the Renovate rules for keeping the
`jdx/hk` and `hugoh/hk-config` pins current live — not in the generic
[`hugoh/renovate-config`](https://github.com/hugoh/renovate-config) fleet
preset, since these rules encode this repo's own release semantics.
`renovate-config`'s own preset extends this file, so every repo that already
extends `renovate-config` picks these rules up transitively with no changes
of its own. It covers:

- Bumping the `hugoh/hk-config` pin in `.pkl` files (as before).
- Bumping the `jdx/hk` pin in both `.pkl` files and `mise.toml`'s
  `hk = "..."` entry together, grouped into a single PR
  (`groupName: "hk toolchain"`, shared with the `hugoh/hk-config` bump above)
  — so the Pkl schema pin and the installed CLI version don't drift apart,
  and so an hk-config bump and the hk version bump it corresponds to land in
  the same review.
- Disabling Renovate's built-in `mise` manager for `hk` specifically, so it
  doesn't also open a second, independently-timed PR for the same
  `mise.toml` line.

Checked via the `renovate-config-validator` step in `hk.pkl` on every commit/push.

## Versioning and releases

Releases are automatic, same as
[`gh-workflows`](https://github.com/hugoh/gh-workflows). Every push to `main`
runs `.github/workflows/release.yml`, which uses
[`mathieudutour/github-tag-action`](https://github.com/mathieudutour/github-tag-action)
to inspect commits since the last tag and bump semver based on
[Conventional Commits](https://www.conventionalcommits.org/) prefixes
(`fix:` → patch, `feat:` → minor, `BREAKING CHANGE`/`!` → major) — note that
`default_bump: false` means **only** those recognized prefixes cut a release;
`chore:`/`docs:`/etc. commits are no-ops here. Bumping the `jdx/hk` pin in
this repo must therefore be a `fix:` commit, not a `chore:` one, or no new
release is cut for consuming repos to adopt. If nothing since the last tag
warrants a bump, the workflow no-ops — no commit, no tag, no release.

When a bump does happen, the same job packages the project with
`pkl project package` and uploads the four resulting artifacts
(`hk-config@<version>`, `.sha256`, `.zip`, `.zip.sha256`) to the new GitHub
Release — that's what makes the `package://github.com/hugoh/hk-config/
releases/download/v<version>/hk-config@<version>#/<file>.pkl` import URL
resolvable.

`hk check`'s `pkl-package` step runs the same `pkl project package
--skip-publish-check` on every commit (it's the one thing `hk validate`
doesn't cover — `hk validate` only checks `hk.pkl` itself, not the modules
this repo publishes). Only `base.pkl` is actually shipped in the package;
this repo's own tooling config (`hk.pkl`, `dprint.json`, `mise.toml`,
`README.md`) is excluded — partly because it isn't meant for consumption,
partly because `hk.pkl` couldn't be evaluated by the official `pkl` CLI
anyway: it uses the same ad-hoc `["key"] = { field = value }` one-off step
syntax as every other repo's `hk.pkl`, which only hk's own bundled evaluator
(`pklr`) accepts.
