# hk-config

Shared [`hk`](https://hk.jdx.dev/) building blocks for hugoh's repos, published
as a [Pkl package](https://pkl-lang.org/main/current/language-reference/index.html#packages)
via GitHub Releases — no central package registry involved, the release
assets themselves are the package.

## Usage

```pkl
amends "package://github.com/jdx/hk/releases/download/v1.49.0/hk@1.49.0#/Config.pkl"
import "package://github.com/jdx/hk/releases/download/v1.49.0/hk@1.49.0#/Builtins.pkl"
import "package://github.com/hugoh/hk-config/releases/download/v0.1.0/hk-config@0.1.0#/base.pkl" as Base

local linters = new Mapping<String, Step> {
    ...Base.base
    // repo-specific overrides and additions go here, same as before
    ["trailing-ws"] = (Builtins.trailing_whitespace) {
        exclude = List("some/generated/dir/**")
    }
}
```

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
hugoh repo's `hk.pkl` `Common` group: `actionlint`, `pinact`, `conflicts`,
`trailing-ws`, `line-endings`, `newlines`, `case-conflict`, `large-files`,
`executables`, `symlinks`, `gitleaks`, `ghalint`, `markdown` (rumdl), `dprint`,
`zizmor`, `typos`, `mise`.

More group files (e.g. per-language extras) may be added alongside it later —
`base.pkl` is named for being the foundation those would build on top of, not
because it's the only file this package will ever contain.

## Versioning and releases

Releases are automatic, same as
[`gh-workflows`](https://github.com/hugoh/gh-workflows). Every push to `main`
runs `.github/workflows/release.yml`, which uses
[`mathieudutour/github-tag-action`](https://github.com/mathieudutour/github-tag-action)
to inspect commits since the last tag and bump semver based on
[Conventional Commits](https://www.conventionalcommits.org/) prefixes
(`fix:` → patch, `feat:` → minor, `BREAKING CHANGE`/`!` → major). If nothing
since the last tag warrants a bump, the workflow no-ops — no commit, no tag,
no release.

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
