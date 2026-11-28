#!/usr/bin/env node
// Checks that the custom managers in presets/hk-pins.json still extract the hk and
// hk-config pins from files shaped like a consumer's hk.pkl / mise.toml.
//
// presets/hk-pins.json only teaches Renovate how to *read* the pins (grouping lives
// in hugoh/renovate-config), so this is the one thing that can silently rot
// when the pin format changes: the regexes stop matching and Renovate just
// stops opening hk PRs. Each fixture is run through Renovate's own regex
// extractor and compared against what a human would expect.
//
// Also runs on this repo's real hk.pkl, mise.toml and base.pkl, so a format
// change here fails the check before it reaches consumers.
//
// Renovate is located via RENOVATE_DIR, or `mise where npm:renovate` (the
// mise-installed npm:renovate pinned in mise.toml).
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(
  readFileSync(join(root, "presets", "hk-pins.json"), "utf8"),
);

function isRenovate(dir) {
  const pkg = join(dir, "package.json");
  return (
    existsSync(pkg) && JSON.parse(readFileSync(pkg, "utf8")).name === "renovate"
  );
}

// Depth-limited search for a `renovate` package directory. mise/aube install
// it under node_modules/.mise/renovate@<ver>_<deps>/node_modules/renovate.
function search(dir, depth) {
  if (isRenovate(dir)) return dir;
  if (depth === 0) return undefined;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
    try {
      const found = search(join(dir, entry.name), depth - 1);
      if (found) return found;
    } catch {
      // unreadable or dangling entry: keep looking
    }
  }
  return undefined;
}

function findRenovate() {
  if (process.env.RENOVATE_DIR) return resolve(process.env.RENOVATE_DIR);
  const where = execFileSync("mise", ["where", "npm:renovate"], {
    encoding: "utf8",
  }).trim();
  const found = search(where, 7);
  if (!found)
    throw new Error(`no renovate package under ${where}; set RENOVATE_DIR`);
  return found;
}

const mod = await import(
  join(
    findRenovate(),
    "dist",
    "modules",
    "manager",
    "custom",
    "regex",
    "index.js",
  )
);
const extractPackageFile =
  mod.extractPackageFile ?? mod.default?.extractPackageFile;

// Every dependency the managers extract from `content`, as sorted
// "dep@version from package/extractVersion (datasource)" strings.
async function extract(file, content) {
  const found = [];
  for (const manager of config.customManagers) {
    const applies = manager.managerFilePatterns.some((p) =>
      new RegExp(p.slice(1, -1)).test(file),
    );
    if (!applies) continue;
    const result = await extractPackageFile(content, file, manager);
    for (const dep of result?.deps ?? []) {
      const name = dep.packageName ?? dep.depName;
      found.push(
        `${dep.depName ?? name}@${dep.currentValue} from ${name}/${dep.extractVersion} (${dep.datasource})`,
      );
    }
  }
  return found.sort();
}

// Consumers are only offered an hk that an hk-config release advertises as an
// hk-vX.Y.Z release; from hk 2.13 any other pairing fails to load.
const hk = (v) =>
  `jdx/hk@${v} from hugoh/hk-config/^hk-v(?<version>.*)$ (github-releases)`;
const hkConfig = (v) =>
  `hugoh/hk-config@${v} from hugoh/hk-config/^v(?<version>.*)$ (github-tags)`;

const fixture = (name) =>
  readFileSync(join(root, "test", "fixtures", name), "utf8");
const real = (name) => readFileSync(join(root, name), "utf8");

// A consumer's amends + two imports, one of them an unrelated package.
const cases = [
  [
    "fixture hk.pkl",
    "hk.pkl",
    fixture("hk.pkl"),
    [hk("2.0.1"), hk("2.0.1"), hkConfig("2.0.1")],
  ],
  // base.pkl: two package imports and the min_hk_version line.
  [
    "fixture base.pkl",
    "base.pkl",
    fixture("base.pkl"),
    [hk("2.0.1"), hk("2.0.1"), hk("2.0.1")],
  ],
  ["fixture mise.toml", "mise.toml", fixture("mise.toml"), [hk("2.0.1")]],
  [
    "fixture mise.toml (table form)",
    "mise.toml",
    fixture("mise-table.toml"),
    [hk("2.0.1")],
  ],
];

let failed = false;
for (const [name, file, content, expected] of cases) {
  const got = await extract(file, content);
  const ok = JSON.stringify(got) === JSON.stringify([...expected].sort());
  if (!ok) failed = true;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
  if (!ok) {
    console.log(`     expected: ${JSON.stringify([...expected].sort())}`);
    console.log(`     got:      ${JSON.stringify(got)}`);
  }
}

// Real files: only require that each still yields an hk pin, so a format
// change here is caught without hard-coding the current version.
for (const [file, minimum] of [
  ["hk.pkl", 2],
  ["base.pkl", 3],
  ["mise.toml", 1],
]) {
  const got = (await extract(file, real(file))).filter((d) =>
    d.startsWith("jdx/hk@"),
  );
  const ok = got.length >= minimum;
  if (!ok) failed = true;
  console.log(
    `${ok ? "ok  " : "FAIL"} real ${file}: ${got.length} jdx/hk pin(s) (need >= ${minimum})`,
  );
}

if (failed) {
  console.error(
    "\nThe custom managers in presets/hk-pins.json no longer read the hk pins as expected.",
  );
  process.exit(1);
}

// hk-config itself must follow upstream hk, or no new hk is ever advertised.
// Run the preset's and this repo's rules through Renovate's own rule engine.
const rules = await import(
  join(findRenovate(), "dist", "util", "package-rules", "index.js")
);
const own = JSON.parse(readFileSync(join(root, "renovate.json"), "utf8"));
const [dep] = (
  await Promise.all(
    config.customManagers.map((m) =>
      extractPackageFile(fixture("mise.toml"), "mise.toml", m),
    ),
  )
).flatMap((result) => result?.deps ?? []);
const resolved = await rules.applyPackageRules({
  ...dep,
  manager: "custom.regex",
  packageRules: [...config.packageRules, ...own.packageRules],
});
const upstream = `${resolved.packageName}/${resolved.extractVersion} (${resolved.datasource})`;
const wanted = "jdx/hk/^v?(?<version>.*)$ (github-releases)";
console.log(`${upstream === wanted ? "ok  " : "FAIL"} hk-config tracks upstream hk`);
if (upstream !== wanted) {
  console.error(`     expected: ${wanted}\n     got:      ${upstream}`);
  process.exit(1);
}
