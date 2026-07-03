const fs = require("fs");
const path = require("path");

const ROOT = process.cwd();
const IGNORE_DIRS = new Set(["node_modules", ".git", "dist", "out", ".vscode"]);
const TEXT_EXT = new Set([
  ".ts", ".tsx", ".js", ".jsx",
  ".json", ".md", ".yml", ".yaml",
  ".css", ".scss", ".html", ".txt"
]);

function isTextFile(file) {
  const ext = path.extname(file).toLowerCase();
  return TEXT_EXT.has(ext);
}

function normalizeContent(buf) {
  // strip BOM
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) {
    buf = buf.slice(3);
  }
  let s = buf.toString("utf8");
  // CRLF/CR -> LF
  s = s.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  return s;
}

function scan(dir, changed = []) {
  for (const entry of fs.readdirSync(dir)) {
    const full = path.join(dir, entry);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      if (!IGNORE_DIRS.has(entry)) scan(full, changed);
    } else {
      if (isTextFile(full)) {
        const orig = fs.readFileSync(full);
        const norm = normalizeContent(orig);
        if (!orig.equals(Buffer.from(norm, "utf8"))) {
          fs.writeFileSync(full, norm, { encoding: "utf8" }); // no BOM
          changed.push(full);
        }
      }
    }
  }
  return changed;
}

const changed = scan(ROOT, []);
if (changed.length) {
  console.log("Normalized (LF + no BOM):");
  changed.forEach(f => console.log("  " + f));
} else {
  console.log("Already normalized ✓");
}