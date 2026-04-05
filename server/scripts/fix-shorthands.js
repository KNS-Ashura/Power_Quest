//fichier de config pour remplacer les shorthands de destructuration dans index.js sinon tout plante
const fs = require("fs");
const path = require("path");

const file = path.join(__dirname, "..", "modules", "index.js");
let src = fs.readFileSync(file, "utf8");

// Remplace { word } et { word, word2 } etc. par leur forme explicite
src = src.replace(/\{\s*(\w+)\s*\}/g, function (_, name) {
  return "{ " + name + ": " + name + " }";
});

fs.writeFileSync(file, src);
console.log("[fix-shorthands] OK -", file);
