// Checks the Japanese of each file given with textlint, with the settings
// of config.mjs, and writes a report as JSON to <work>/textlint.json:
// {files: [{file, findings: [{line, check, level, message}]}], notes:
// [{file, reason}]}, with a note for each file of a format that textlint
// doesn't read. A rule can print to stdout, so the report goes to a file
// of its own. Any other failure stops Node, and lib/lib.sh shows it.
//
// Usage: node check.mjs <node_modules> <work> <file>...
//
// It lints each file by its text, not by its path, as textlint reads a
// path as a glob: the name [x].md would match only x.md.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { settings } from "./config.mjs";

const [modules, work, ...files] = process.argv.slice(2);
const require = createRequire(path.join(path.resolve(modules), "x.js"));
const { loadConfig } = require("@textlint/config-loader");
const { builtInPlugins, loadBuiltinPlugins } = require("textlint/lib/src/loader/TextlintrcLoader.js");
const { createLinter } = require("textlint");

// The rules of the checks, by their keys in the settings, with the file of
// each. textlint finds a rule only in node_modules, so the checks load
// these themselves, with the options of the settings.
const own = { "ja-no-unneeded-comma": "./unneeded-comma.mjs" };

// Loads settings $config, the $n-th, for textlint.
async function load(config, n) {
  const settingsRules = { ...config.rules };
  const ownRules = [];
  for (const [ruleId, file] of Object.entries(own)) {
    const options = settingsRules[ruleId];
    delete settingsRules[ruleId];
    if (options === undefined || options === false) continue;
    const rule = (await import(new URL(file, import.meta.url))).default(require);
    ownRules.push({ ruleId, rule, options: options === true ? {} : options });
  }
  const configFilePath = path.join(work, `textlintrc-${n}.json`);
  fs.writeFileSync(configFilePath, JSON.stringify({ ...config, rules: settingsRules }, null, 2));
  const loaded = await loadConfig({ configFilePath, node_modulesDir: modules });
  if (!loaded.ok) throw new Error([loaded.error.message, ...loaded.error.errors.map((error) => error.message)].join(": "));
  const { plugins, filterRules } = loaded.config;
  const rules = [...loaded.config.rules, ...ownRules];
  // The level that the settings give each rule, by the ID that textlint
  // reports. textlint drops this level from a finding that a rule reports
  // as a plain object, not as a RuleError, as ai-tech-writing-guideline of
  // preset-ai-writing does, so the checks give the finding this level.
  const levels = Object.fromEntries(rules.filter((rule) => typeof rule.options?.severity === "string").map((rule) => [rule.ruleId, rule.options.severity]));
  // The descriptor that loadTextlintrc of textlint builds from the same
  // settings, with the plugins that textlint always has first.
  const descriptor = (await loadBuiltinPlugins()).shallowMerge({ rules, filterRules, plugins: [...builtInPlugins, ...plugins], configBaseDir: work });
  // A plugin reads an extension only if no plugin before it reads it.
  const extensions = [...new Set(descriptor.availableExtensions)].join(", ");
  return { levels, descriptor, extensions, linter: createLinter({ descriptor }) };
}

// The linter of each settings file, which config.mjs finds for the
// directory of each file.
const linters = new Map();
const report = { files: [], notes: [] };
for (const file of files) {
  const { config, source } = settings(modules, path.dirname(path.resolve(file)), process.cwd());
  if (!linters.has(source)) linters.set(source, await load(config, linters.size));
  const { levels, descriptor, extensions, linter } = linters.get(source);
  if (!descriptor.findPluginDescriptorWithExt(path.extname(file))) {
    report.notes.push({ file, reason: `textlint reads only the files that end in ${extensions}` });
    continue;
  }
  const result = await linter.lintText(fs.readFileSync(file, "utf8"), path.resolve(file));
  // textlint gives each finding a level by number: 1 warning, 2 error and 3
  // info. The level that the settings name for a rule comes first.
  const findings = result.messages.map((message) => ({
    line: message.line,
    check: message.ruleId,
    level: levels[message.ruleId] || { 1: "warning", 2: "error", 3: "info" }[message.severity] || "error",
    message: message.message,
  }));
  report.files.push({ file, findings });
}
fs.writeFileSync(path.join(work, "textlint.json"), JSON.stringify(report));
