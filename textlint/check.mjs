// Checks the Japanese of each file given with textlint, with the settings
// of config.mjs, and prints a report as JSON:
// {source, files: [{file, findings: [{line, check, level, message}]}], notes}.
// A file that textlint doesn't check gets a note of why, and fails, as
// "What it checks" in README.md says. Settings that textlint can't load
// print {error} and exit 1.
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
const require = createRequire(path.join(path.resolve(modules), "x.js"));

// The files that textlint leaves out of each search, as
// DEFAULT_IGNORE_PATTERNS of textlint/lib/src/util/find-util.js says.
// tests/run.sh checks that textlint still has them.
const leftOut = ["**/.git/**", "**/node_modules/**"];

// Whether textlint would leave out the file at the absolute path $file
// with the glob patterns $ignore, as it reads them from directory $start.
async function ignored(file, ignore) {
  const { glob, escape } = require("glob");
  const found = await glob(escape(file, { magicalBraces: true }), { cwd: start, absolute: true, nodir: true, dot: true, ignore });
  return found.length === 0;
}

// The patterns of .textlintignore in directory $start, which textlint
// reads by default, with no empty line and no comment.
function textlintignore() {
  const file = path.join(start, ".textlintignore");
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, "utf8").split(/\r?\n/).filter((line) => !/^\s*$/.test(line) && !/^\s*#/.test(line));
}

async function main() {
  const { config, levels, source } = settings(modules, start);
  const configFilePath = path.join(work, "textlintrc.json");
  fs.writeFileSync(configFilePath, JSON.stringify(config, null, 2));
  // loadTextlintrc gives textlint no rule at all when the settings fail to
  // load, so loadConfig says why first.
  const { loadConfig } = require("@textlint/config-loader");
  const loaded = await loadConfig({ configFilePath, node_modulesDir: modules });
  if (!loaded.ok) {
    const reasons = (loaded.error.errors || []).map((error) => error.message);
    throw new Error([loaded.error.message, ...reasons].join(": "));
  }
  const { createLinter, loadTextlintrc } = require("textlint");
  const descriptor = await loadTextlintrc({ configFilePath, node_modulesDir: modules });
  const linter = createLinter({ descriptor, cwd: start });
  const formats = descriptor.plugin.descriptors.map((plugin) => `${plugin.id} (${plugin.availableExtensions.join(", ")})`).join(", ");
  const ignore = textlintignore();
  const fix = "Fix: leave the file out of the job japanese, with glob or exclude in lefthook.yml.";
  const report = { source, files: [], notes: [] };
  for (const file of files) {
    if (!descriptor.findPluginDescriptorWithExt(path.extname(file))) {
      report.notes.push(`textlint didn't check ${file}, as it reads only the formats of its plugins: ${formats}. ${fix}`);
      continue;
    }
    if (await ignored(file, leftOut)) {
      report.notes.push(`textlint didn't check ${file}, as it leaves out each file in node_modules and .git. ${fix}`);
      continue;
    }
    // The repository leaves this file out.
    if (ignore.length > 0 && (await ignored(file, ignore))) continue;
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
      report.notes.push(`textlint didn't check ${file}: ${error.message}`);
    }
  }
  return report;
}

try {
  process.stdout.write(JSON.stringify(await main()));
} catch (error) {
  process.stdout.write(JSON.stringify({ error: error.message }));
  process.exitCode = 1;
}
