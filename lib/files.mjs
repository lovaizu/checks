// Sorts the files given for prose.sh, and prints as JSON the report of the
// files that the checks can't read, {files: [], notes: [{file, kind,
// reason}]}, with texts: the files that the tools check. A path in texts is
// absolute, with no link, . or .. in its directory, as Vale reports it, so
// that each finding finds its file.
//
// Usage: node files.mjs <file>...
//
// A file that isn't there is a file that the commit deletes. A link is
// checked as the file that it points to, under the path of the link, as a
// glob of the job can leave out that file. A link out of the repository,
// the current directory, fails: the repository doesn't hold its text. A
// file with a NUL byte, such as an image, holds no text. The checks read
// text in UTF-8 alone: a tool reads other bytes as text that the file
// doesn't hold, or fails, so each other file fails here.
import fs from "node:fs";
import path from "node:path";

const decoder = new TextDecoder("utf-8", { fatal: true });
const repository = process.cwd();
const report = { files: [], notes: [], texts: [] };
for (const file of process.argv.slice(2)) {
  let bytes;
  try {
    const link = fs.lstatSync(file);
    if (!link.isFile() && !link.isSymbolicLink()) continue;
    const target = fs.realpathSync(file);
    if (!target.startsWith(repository + path.sep)) {
      report.notes.push({ file, kind: "file", reason: `it's in ${target}, out of the repository` });
      continue;
    }
    if (!fs.statSync(target).isFile()) continue;
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
  report.texts.push(path.join(fs.realpathSync(path.dirname(path.resolve(file))), path.basename(file)));
}
console.log(JSON.stringify(report));
