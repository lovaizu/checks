// Checks the Japanese of each file given with textlint, with the settings
// of config.mjs, and writes a report as JSON to <work>/textlint.json:
// {source, files: [{file, findings: [{line, check, level, message}]}], notes},
// or {error} when textlint can't load the settings. A rule can print to
// stdout, so the report goes to a file of its own.
//
// Usage: node check.mjs <node_modules> <directory> <work> <file>...
//
// It lints each file by its text, not by its path, as textlint reads a
// path as a glob: the name [x].md would match only x.md. A failure of one
// file then leaves the findings of the others.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { settings } from "./config.mjs";

const [modules, start, work, ...files] = process.argv.slice(2);
// A reason with no period at its end, to which a fix follows.
const reason = (text) => text.split("\n")[0].replace(/[.\s]+$/, "");
const require = createRequire(path.join(path.resolve(modules), "x.js"));

// The files that the repository leaves out in the .textlintignore of
// directory $start, which textlint reads by default, as textlint matches
// its patterns.
async function ignoredFiles() {
  const file = path.join(start, ".textlintignore");
  if (!fs.existsSync(file)) return new Set();
  const { glob, escape } = require("glob");
  const ignore = fs.readFileSync(file, "utf8").split(/\r?\n/).filter((line) => !/^\s*$/.test(line) && !/^\s*#/.test(line));
  const left = new Set();
  for (const name of files) {
    const found = await glob(escape(name, { magicalBraces: true }), { cwd: start, absolute: true, nodir: true, dot: true, ignore });
    if (found.length === 0) left.add(name);
  }
  return left;
}

// The fix of settings that textlint can't load.
const fixSettings = "Fix: in the settings of textlint of the repository, turn off or remove each rule, filter and plugin that textlint/package.json of lovaizu/checks doesn't install.";

// The first line of each reason that textlint gives for the settings that
// it can't load. The rest asks to install a package, which a repository
// can't do in the node_modules of the checks.
async function loadError(configFilePath) {
  const { loadConfig } = require("@textlint/config-loader");
  const { error } = await loadConfig({ configFilePath, node_modulesDir: modules });
  const reasons = [error?.message, ...(error?.errors || []).map((e) => reason(e.message))].filter(Boolean);
  return `${reasons.join(": ") || "textlint loaded no rule"}. ${fixSettings}`;
}

async function main() {
  const { config, levels, source } = settings(modules, start);
  const configFilePath = path.join(work, "textlintrc.json");
  fs.writeFileSync(configFilePath, JSON.stringify(config, null, 2));
  const { createLinter, loadTextlintrc } = require("textlint");
  // loadTextlintrc gives textlint no rule when the settings fail to load,
  // and the settings of the checks always have rules.
  const descriptor = await loadTextlintrc({ configFilePath, node_modulesDir: modules });
  if (descriptor.rule.descriptors.length === 0) return { error: await loadError(configFilePath) };
  const linter = createLinter({ descriptor, cwd: start });
  // A plugin reads an extension only if no plugin before it reads it.
  const extensions = [...new Set(descriptor.availableExtensions)].join(", ");
  const ignored = await ignoredFiles();
  const report = { source, files: [], notes: [] };
  for (const file of files) {
    if (ignored.has(file)) continue;
    if (!descriptor.findPluginDescriptorWithExt(path.extname(file))) {
      report.notes.push(`textlint didn't check ${file}, as it reads only the files that end in ${extensions}. Fix: leave the file out of the job japanese, with glob or exclude in lefthook.yml.`);
      continue;
    }
    try {
      const result = await linter.lintText(fs.readFileSync(file, "utf8"), file);
      // textlint gives each finding a level by number: 1 warning, 2 error
      // and 3 info. The level that the settings name for a rule comes first.
      const findings = result.messages.map((message) => ({
        line: message.line,
        check: message.ruleId,
        level: levels[message.ruleId] || { 1: "warning", 2: "error", 3: "info" }[message.severity] || "error",
        message: message.message,
      }));
      report.files.push({ file, findings });
    } catch (error) {
      report.notes.push(`textlint didn't check ${file}: ${reason(error.message)}. Fix: turn off in the settings of textlint of the repository the rule that fails on the file, or leave the file out of the job japanese.`);
    }
  }
  return report;
}

let report;
try {
  report = await main();
} catch (error) {
  // config.mjs gives the fix of each file that it can't read, and a preset
  // that isn't installed fails as a module that isn't found.
  report = { error: error.message.includes("Fix:") ? error.message : `${reason(error.message)}. ${fixSettings}` };
}
fs.writeFileSync(path.join(work, "textlint.json"), JSON.stringify(report));
