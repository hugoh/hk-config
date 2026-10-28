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
today — only the boilerplate step *definitions* move here, the per-repo
customization stays local.

This repo's own `hk.pkl` does the same thing, importing `base.pkl` locally
(`import "base.pkl"`, not the package URL — no bootstrapping problem, since
it's just reading a sibling file off disk).

## What's in `base.pkl`

The lowest-common-denominator step set found active, unmodified, across every
hugoh repo's `hk.pkl` `Common` group: `jactionlint`, `pinact`,
`check_merge_conflict`, `trailing_whitespace`, `mixed_line_ending`,
`newlines`, `check_case_conflict`, `check_added_large_files`,
`check_executables_have_shebangs`, `check_symlinks`, `gitleaks`,
`ghalint_workflow`, `rumdl`, `rumdl_format`, `biome`, `zizmor`, `typos`,
`mise`, `tombi`, `tombi_format`, `ryl`, `ryl_format`, `hk_pin_sync`. Keys match
the `Builtins` identifier they map to, so the step name always tells you which
builtin is running.

`biome` covers JSON as well as JS/TS/JSX — that's why `dprint` (previously
the only JSON formatter in the shared set) was dropped: dprint's `json` and
`biome` plugins were doing overlapping, redundant work on the same files, and
a native binary (biome) is lighter than dprint's WASM plugin pipeline. Repos
that still need markdown/toml/yaml/JSON formatting beyond what
rumdl/tombi/ryl/biome already lint get that from those dedicated steps now,
not from a separate dprint config.

`tf` is the OpenTofu/Terraform group: `tf_lint` (tflint), `tofu` (`tofu fmt`),
`tf_security` — a `trivy config` misconfiguration scan gated to HIGH/CRITICAL —
and `tofu_validate` (`tofu init` + `tofu validate`). `tf_security` runs `trivy
config` over the repo root rather than per-file, so it re-runs whenever any
`*.tf` file changes. `tofu_validate` is gated to the `ci` profile (it needs
`tofu init` with network access), so it only runs under `hk check --profile
ci` — which the shared `hugoh/gh-workflows/hk-check` action does. Spread
`...Base.tf` in alongside `...Base.base`; encrypted `*.tfstate` excludes on the
text-hygiene steps stay a local override, same as any other repo
customization.

The per-language opt-in groups, spread in alongside `base`: `python` (`ruff`,
`ruff_format`, `ty`), `shell` (`shellcheck`, `shellharden`, `shfmt`), and
`lua` (`selene`, `stylua`). Two more are opt-in but not spread automatically
because they need network access and/or credentials: `renovate`
(`renovate_config_validator`) and `checkly` (`checkly_preview`) — see the
doc-comments in `base.pkl` for where it's safe to wire them into hooks.

More group files (e.g. per-language extras) may be added alongside it later —
`base.pkl` is named for being the foundation those would build on top of, not
because it's the only file this package will ever contain.

`commit_msg` (`check_conventional_commit`) is separate from `base`/`python`/
`shell`/`lua`/`tf`: it needs `commit_msg_file`, which only exists inside a
`commit-msg` hook, so spread it into that hook's `steps` specifically —
spreading it into the shared `linters` mapping used by
check/pre-commit/pre-push/fix fails with "Variable `commit_msg_file` is not
defined".

`hk_pin_sync` fails if the consuming repo's `hk.pkl` `amends`/`import` hk pins
disagree, or if an `hk = "..."` entry in its `mise.toml` differs from the
`hk.pkl` pin. It does not compare against `min_hk_version` (below): hk itself
refuses to run when the binary is older, and a newer hk passes, so a new hk
release landing before hk-config has adopted it doesn't turn CI red;
hk-config only needs a release when it needs a newer hk.
`scripts/check-hk-pin-sync.sh` (the `hk-pin-sync` step in `hk.pkl`) exercises
the check against throwaway consumer repos.

`stepTools` maps every step key to the mise tool it runs, spelled as consuming
repos pin it in `mise.toml` (`null` for steps that run hk or mise themselves, or
use an unpinned tool such as `npx`). `scripts/check-step-tools.sh` (the
`step-tools` step in `hk.pkl`) fails if it drifts from `allStepKeys`, so a new
step can't merge without declaring its tool.
[`hugoh/renovate-config`](https://github.com/hugoh/renovate-config) reads
`stepTools` in its own `check-package-rules.mjs` to check that every pinned
linter is classified in its Renovate rules: when you add a step whose tool is a
linter, add that tool to the `linters` rule in renovate-config's `default.json`
(or to the exclusion list in the check script, with a reason). A tool left out
just stays on the weekly schedule.

## Migrating from v2 to v3

v3 replaces the `actionlint` step with `jactionlint`
([jdx/jactionlint](https://github.com/jdx/jactionlint), an actionlint fork), so
it needs hk 2.7.0 or newer. `scripts/migrate-v3.sh [repo-dir]` does the
consumer-side changes, idempotently: it renames the `actionlint` tool in
`mise.toml` to `jactionlint` (version from `JACTIONLINT_VERSION`), renames
`actionlint` step overrides in `hk.pkl` (and rewrites `["key"] = {` steps to
`["key"] {`, which hk 2.6.0 requires), and moves `.github/actionlint.yaml` to
`.github/jactionlint.yaml`, adding `profile: default` if the file sets no
profile. It also bumps the hk pins together (the `hk.pkl` amends/import URLs,
a literal `min_hk_version`, and `mise.toml`'s `hk =`) to the latest stable hk
release, or to `HK_VERSION`, leaving a pin that is already newer alone, and
points the `hk.pkl` hk-config import at the latest v3 release, or at
`HK_CONFIG_VERSION`. Both lookups use `git ls-remote`; if one finds nothing
(no v3 hk-config is released yet, or there is no network) it says so and
leaves that pin. Finally it runs `mise install` and `jactionlint` (through
`mise exec`, so the pinned version is used) over the workflows and, if that
finds issues, prints what to change (the `default` profile adds rules
actionlint never had, such as `concurrency-limits` and
`excessive-permissions`); that report doesn't change its exit status. The last
step is `hk check --all` (through `mise exec`, or `HK_BIN`), and the script
exits with its status, so it only succeeds when the migrated repo passes. The
script is zsh, so it runs as is on macOS.
`scripts/check-migrate-v3.sh` (the `migrate-v3` step in `hk.pkl`) runs it over
throwaway repos.

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
  `hk = "..."` entry together.
- Disabling Renovate's built-in `mise` manager for `hk` specifically, so it
  doesn't also open a second, independently-timed PR for the same
  `mise.toml` line.

What this file deliberately does **not** do is group or schedule those bumps:
that is the extending hub's job. An hk-config release can require a newer hk
(`min_hk_version`), and fails the consumer's CI until the `jdx/hk` bump lands,
so both hubs bump the two together, in one PR with one 7-day soak (a shorter
hk-config soak would let it mature before the hk it needs):
[`renovate-config`](https://github.com/hugoh/renovate-config)'s `default.json`
in its monthly `linters` group (see its README, "The hk pins"), and go-tools in
its `dev tools` groups. In this repo, hk is part of the project rather than a
tool it lints with, so it stays in the generic groups.

Checked via the `renovate-config-validator` step in `hk.pkl` on every commit/push.
The `renovate-managers` step (`scripts/check-renovate-managers.mjs`) goes
further: it runs the custom managers through Renovate's own regex extractor
over `test/fixtures/` (shaped like a consumer's `hk.pkl` and `mise.toml`, plus
similar-looking keys that must *not* match) and over this repo's real pins. A
change to the pin format that makes the regexes stop matching therefore fails
here instead of silently stopping Renovate's hk PRs. The fixtures are not part
of the package.

## Versioning and releases

Releases are automatic, same as
[`gh-workflows`](https://github.com/hugoh/gh-workflows). Every push to `main`
runs `.github/workflows/release.yml`, a thin caller of the reusable
[`hugoh/gh-workflows/.github/workflows/release.yml`](https://github.com/hugoh/gh-workflows/blob/main/.github/workflows/release.yml),
which runs [`hugoh/cog-bump`](https://github.com/hugoh/cog-bump) (cocogitto) to
inspect commits since the last tag and bump semver based on
[Conventional Commits](https://www.conventionalcommits.org/) prefixes
(`fix:` → patch, `feat:` → minor, `BREAKING CHANGE`/`!` → major) — only those
recognized prefixes cut a release; `chore:`/`docs:`/etc. commits are no-ops.
Bumping the `jdx/hk` pin in this repo must therefore be a `fix:` commit, not a
`chore:` one, or no new release is cut for consuming repos to adopt. If nothing
since the last tag warrants a bump, the workflow no-ops — no commit, no tag, no
release.

When a bump does happen, the reusable's `package-command` /
`package-artifacts` inputs (set in the caller to `pkl project package
--output-path dist` / `dist/*`) package the project and upload the four
resulting artifacts (`hk-config@<version>`, `.sha256`, `.zip`, `.zip.sha256`)
to the new GitHub Release — that's what makes the
`package://github.com/hugoh/hk-config/releases/download/v<version>/hk-config@<version>#/<file>.pkl`
import URL resolvable.

`hk check`'s `pkl-package` step runs the same `pkl project package
--skip-publish-check` on every commit (it's the one thing `hk validate`
doesn't cover — `hk validate` only checks `hk.pkl` itself, not the modules
this repo publishes). `hk check`'s `readme-steps` step
(`scripts/check-readme-steps.sh`) covers the other sync gap: it evaluates
`base.pkl`'s `allStepKeys` and fails if this README's *What's in `base.pkl`*
section doesn't mention one of them — so adding a step without documenting it
breaks the build. Only `base.pkl` is actually shipped in the package;
this repo's own tooling config (`hk.pkl`, `biome.json`, `mise.toml`,
`README.md`, `scripts/`) is excluded — partly because it isn't meant for consumption,
partly because `hk.pkl` couldn't be evaluated by the official `pkl` CLI
anyway: it uses the same ad-hoc `["key"] = { field = value }` one-off step
syntax as every other repo's `hk.pkl`, which only hk's own bundled evaluator
(`pklr`) accepts.
