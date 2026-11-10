// Sorts the files given for prose.sh, and prints as JSON the report of the
// files that the checks can't read, {files: [], notes: [{file, kind,
// reason}]}, with texts: the files that the tools check, and names: the
// path in the repository of each file given, by the file in texts that it
// is. A path in texts is absolute, with no link, . or .. in it, as Vale
// reports it, so that each finding finds its file.
//
// Usage: node files.mjs <file>...
//
// A file that isn't there is a file that the commit deletes. A link is
// checked as the file that it points to, in the format of that file, and
// its findings show under the path of the link, as a glob of the job can
// leave out that file. A link out of the repository, the current
// directory, fails: the repository doesn't hold its text. A link to no
// file, like a file with a NUL byte, such as an image, holds no text. The
// checks read text in UTF-8 alone: a tool reads other bytes as text that
// the file doesn't hold, or fails, so each other file fails here.
import fs from "node:fs";
import path from "node:path";

const decoder = new TextDecoder("utf-8", { fatal: true });
const repository = process.cwd();
const report = { files: [], notes: [], texts: [], names: {} };

// The path of $file with no link in it, though the file isn't there: a link
// to no file leads to where its target would be.
function where(file) {
  try {
    return fs.realpathSync(file);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const dir = where(path.dirname(file));
  const name = path.join(dir, path.basename(file));
  if (fs.lstatSync(name, { throwIfNoEntry: false })?.isSymbolicLink()) return where(path.resolve(dir, fs.readlinkSync(name)));
  return name;
}

for (const file of process.argv.slice(2)) {
  let bytes, target;
  try {
    const link = fs.lstatSync(file);
    if (!link.isFile() && !link.isSymbolicLink()) continue;
    target = where(file);
    if (!target.startsWith(repository + path.sep)) {
      report.notes.push({ file, kind: "file", reason: `it's in ${target}, out of the repository` });
      continue;
    }
    if (!fs.statSync(target, { throwIfNoEntry: false })?.isFile()) continue;
    bytes = fs.readFileSync(target);
  } catch (error) {
    if (error.code === "ENOENT" && error.syscall === "lstat") continue;
    report.notes.push({ file, kind: "file", reason: `the checks couldn't read it: ${error.message}` });
    continue;
  }
  if (bytes.includes(0)) continue;
  try {
    decoder.decode(bytes);
  } catch {
    report.notes.push({ file, kind: "file", reason: "it isn't text in UTF-8, the only encoding that the checks read" });
    continue;
  }
  if (!report.names[target]) {
    report.texts.push(target);
    report.names[target] = [];
  }
  report.names[target].push(path.relative(repository, path.join(where(path.dirname(path.resolve(file))), path.basename(file))));
}
console.log(JSON.stringify(report));
