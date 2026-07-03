const fs = require("fs");
const path = require("path");
const ROOT = process.cwd();
const IGNORE = new Set(["node_modules",".git","dist","out",".vscode"]);
function scan(dir, bad=[]){
  for(const e of fs.readdirSync(dir)){
    const f = path.join(dir, e);
    const s = fs.statSync(f);
    if(s.isDirectory()){ if(!IGNORE.has(e)) scan(f,bad); }
    else {
      const base = path.basename(f);
      if(base !== base.normalize("NFC")) bad.push(f);
    }
  }
  return bad;
}
const bad = scan(ROOT);
if(bad.length){ console.error("❌ Files with non-NFC names:"); bad.forEach(f=>console.error("  "+f)); process.exit(1); }
else { console.log("✔ All file names NFC-normalized"); }