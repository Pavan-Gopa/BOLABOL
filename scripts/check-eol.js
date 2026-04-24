const fs = require("fs");
const path = require("path");
const ROOT = process.cwd();
const IGNORE = new Set(["node_modules",".git","dist","out",".vscode"]);
const TEXT = new Set([".ts",".tsx",".js",".jsx",".json",".md",".yml",".yaml",".css",".scss",".html",".txt"]);
const isText = f => TEXT.has(path.extname(f).toLowerCase());
function scan(dir, bad=[]){
  for(const e of fs.readdirSync(dir)){
    const f = path.join(dir, e);
    const s = fs.statSync(f);
    if(s.isDirectory()){ if(!IGNORE.has(e)) scan(f,bad); }
    else if(isText(f)){
      const buf = fs.readFileSync(f,"utf8");
      if(buf.includes("\r\n")) bad.push(f);
    }
  }
  return bad;
}
const bad = scan(ROOT);
if(bad.length){ console.error("❌ Files with CRLF:"); bad.forEach(f=>console.error("  "+f)); process.exit(1); }
else { console.log("✔ No CRLF endings detected"); }