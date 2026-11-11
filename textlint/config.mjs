// The textlint settings that the checks use: the defaults of
// .textlintrc.json, with the settings of the repository laid over them.
// textlint reads only one settings file, so the checks give it this one.
//
// It finds the settings of the repository as textlint itself does, from a
// directory up, but only up to the root of the repository, as a settings
// file above it is of another repository: in each directory, .textlintrc.cjs,
// .textlintrc.js, .textlintrc.json, .textlintrc.yaml, .textlintrc.yml and
// .textlintrc, then the field textlint of package.json. "Change a setting"
// in README.md says how the settings of the repository lie over the
// defaults.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

// Reads file $file by function $read, and fails where the file isn't valid.
function parse(file, read) {
  try {
    return read(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new Error(`textlint couldn't read ${file}: ${error.message}`);
  }
}

// Finds the settings of the repository from directory $dir up to the root
// of the repository, $root, with the function $require that loads the
// modules of textlint. A JavaScript file runs to make its settings, so the
// checks can't merge it. textlint reads .textlintrc as JSON or YAML.
function find(require, dir, root) {
  const JSON5 = require("json5");
  const yaml = require("js-yaml");
  for (const name of [".textlintrc.cjs", ".textlintrc.js", ".textlintrc.json", ".textlintrc.yaml", ".textlintrc.yml", ".textlintrc"]) {
    const file = path.join(dir, name);
    if (!fs.existsSync(file)) continue;
    if (name.endsWith("js")) throw new Error(`${file} is JavaScript, which the checks can't merge into their defaults: write it as JSON or YAML`);
    return { file, config: parse(file, name.endsWith(".json") ? JSON5.parse : yaml.load) || {} };
  }
  const pkg = path.join(dir, "package.json");
  if (fs.existsSync(pkg)) {
    const json = parse(pkg, JSON5.parse);
    if (json.textlint) return { file: pkg, config: json.textlint };
  }
  const parent = path.dirname(dir);
  return dir === root || parent === dir ? null : find(require, parent, root);
}

const isObject = (x) => x !== null && typeof x === "object" && !Array.isArray(x);

// A key with no value, null in YAML, is one that the repository doesn't
// write.
function merge(base, over) {
  if (over === undefined || over === null) return base;
  if (isObject(base) && isObject(over)) {
    const out = { ...base };
    for (const [key, value] of Object.entries(over)) out[key] = merge(base[key], value);
    return out;
  }
  if (isObject(base) && over === true) return base;
  if (Array.isArray(base) && Array.isArray(over)) return [...base, ...over.filter((x) => !base.includes(x))];
  return over;
}

// textlint takes the name of a rule, a preset or a filter in short, such as
// prh, or as its package, such as textlint-rule-prh. Each key gets the short
// name, as textlint gives it, so that the two names of a rule merge.
function normalize(require, config) {
  const { normalizeTextlintRuleKey, normalizeTextlintFilterRuleKey } = require("@textlint/utils");
  const keys = (entries, name) => (isObject(entries) ? Object.fromEntries(Object.entries(entries).map(([key, value]) => [name(key), value])) : entries);
  return { ...config, rules: keys(config.rules, normalizeTextlintRuleKey), filters: keys(config.filters, normalizeTextlintFilterRuleKey) };
}

// textlint reads the paths in the options of a rule from the directory of
// its settings file. The merged file lives elsewhere, so each path that
// the repository names becomes absolute.
function resolvePaths(config, dir) {
  const fix = (paths) => (Array.isArray(paths) ? paths.map((p) => (p.startsWith("~") ? p : path.resolve(dir, p))) : paths);
  const prh = config.rules?.prh;
  if (isObject(prh) && prh.rulePaths) prh.rulePaths = fix(prh.rulePaths);
  const allow = config.filters?.allowlist;
  if (isObject(allow) && allow.allowlistConfigPaths) allow.allowlistConfigPaths = fix(allow.allowlistConfigPaths);
  return config;
}

// A key has the short name, such as preset-ja-technical-writing, or
// @textlint-ja/preset-ai-writing.
const isPreset = (key) => /^(@[^/]+\/)?preset-/.test(key);
const loadPreset = (require, key) => {
  const loaded = require(key.replace(/^(@[^/]+\/)?/, "$1textlint-rule-"));
  return loaded.default || loaded;
};

// Returns the settings for the node_modules of textlint, $modules, the
// directory $start where the search begins, and the root of the repository,
// $root, where it ends: {config, source}. source is
// the settings file of the repository, if any.
export function settings(modules, start, root) {
  const require = createRequire(path.join(path.resolve(modules), "x.js"));
  // A preset that the defaults turn on with `true` gets its own settings of
  // each rule, so that the settings of the repository merge into those.
  const defaults = normalize(require, JSON.parse(fs.readFileSync(new URL(".textlintrc.json", import.meta.url), "utf8")));
  for (const [key, value] of Object.entries(defaults.rules)) {
    if (isPreset(key) && value === true) defaults.rules[key] = { ...(loadPreset(require, key).rulesConfig || {}) };
  }
  const found = find(require, path.resolve(start), path.resolve(root));
  const config = found ? merge(defaults, resolvePaths(normalize(require, found.config), path.dirname(found.file))) : defaults;
  return { config, source: found ? found.file : "" };
}
