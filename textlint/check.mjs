// Checks the Japanese of each file given with textlint, with the settings
// of config.mjs, and writes a report as JSON to <work>/textlint.json:
// {source, files: [{file, findings: [{line, check, level, message}]}],
// notes: [{file, kind, reason, detail}]}. A rule can print to stdout, so
// the report goes to a file of its own. lib/lib.sh turns each note into
// its text, with the fix of its kind: format, settings or unknown.
//
// Usage: node check.mjs <node_modules> <directory> <work> <file>...
//
// It lints each file by its text, not by its path, as textlint reads a
// path as a glob: the name [x].md would match only x.md. A failure of one
// file then leaves the findings of the others.
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { settings, SettingsError } from "./config.mjs";

const [modules, start, work, ...files] = process.argv.slice(2);
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

// The plugins that textlint always has, before those of the settings, as
// loadTextlintrc of textlint gives them.
function builtInPlugins() {
  const plugin = (id) => ({ pluginId: id, plugin: require(id).default || require(id), options: true });
  return [plugin("@textlint/textlint-plugin-text"), plugin("@textlint/textlint-plugin-markdown")];
}

async function main() {
  const { config, source } = settings(modules, start);
  const configFilePath = path.join(work, "textlintrc.json");
  fs.writeFileSync(configFilePath, JSON.stringify(config, null, 2));
  const { loadConfig } = require("@textlint/config-loader");
  const loaded = await loadConfig({ configFilePath, node_modulesDir: modules });
  if (!loaded.ok) {
    const reason = [loaded.error.message, ...loaded.error.errors.map((error) => error.message)];
    return { source, files: [], notes: [{ kind: "settings", reason }] };
  }
  const { TextlintKernelDescriptor } = require("@textlint/kernel");
  const { rules, plugins, filterRules } = loaded.config;
  // The level that the settings give each rule, by the ID that textlint
  // reports. textlint drops this level from a finding that a rule reports
  // as a plain object, not as a RuleError, as ai-tech-writing-guideline of
  // preset-ai-writing does, so the checks give the finding this level.
  const levels = Object.fromEntries(rules.filter((rule) => typeof rule.options?.severity === "string").map((rule) => [rule.ruleId, rule.options.severity]));
  const descriptor = new TextlintKernelDescriptor({ rules, filterRules, plugins: [...builtInPlugins(), ...plugins], configBaseDir: work });
  const { createLinter } = require("textlint");
  const linter = createLinter({ descriptor, cwd: start });
  // A plugin reads an extension only if no plugin before it reads it.
  const extensions = [...new Set(descriptor.availableExtensions)].join(", ");
  const ignored = await ignoredFiles();
  const report = { source, files: [], notes: [] };
  for (const file of files) {
    if (ignored.has(file)) continue;
    if (!descriptor.findPluginDescriptorWithExt(path.extname(file))) {
      report.notes.push({ file, kind: "format", reason: `textlint reads only the files that end in ${extensions}` });
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
      report.notes.push({ file, kind: "unknown", reason: error.message, detail: { stack: error.stack } });
    }
  }
  return report;
}

let report;
try {
  report = await main();
} catch (error) {
  const kind = error instanceof SettingsError ? "settings" : "unknown";
  report = { source: "", files: [], notes: [{ kind, reason: error.message, detail: kind === "unknown" ? { stack: error.stack } : undefined }] };
}
fs.writeFileSync(path.join(work, "textlint.json"), JSON.stringify(report));
