// Membuat app/Tests/VectorData.swift: menempelkan JSON vektor sebagai konstanta Swift,
// supaya XCTest tidak bergantung pada resource bundle (yang bermasalah di XcodeGen).
// Jalankan: node app/tools/gen_vector_data.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const tests = join(here, "..", "Tests");

// nama (dipakai test) -> file
const files = [
  ["crc", "crc.json"],
  ["frames", "frames.json"],
  ["link-a-commands", "link-a-commands.json"],
  ["handshake-nmax-turbo", "handshake-nmax-turbo.json"],
  ["share-links", "share-links.json"],
];

// "link-a-commands" -> "linkACommands" (identifier Swift yang valid)
function ident(name) {
  return name.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

function escapeSwift(s) {
  let out = "";
  for (const ch of s) {
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else out += ch;
  }
  return out;
}

let swift = "import Foundation\n\n";
swift += "/// JSON vektor sebagai konstanta Swift (dihasilkan oleh app/tools/gen_vector_data.mjs).\n";
swift += "/// Menghindari ketergantungan pada resource bundle saat menjalankan XCTest.\n";
swift += "enum VectorData {\n";
swift += "    static func raw(_ name: String) -> String? {\n";
swift += "        switch name {\n";
for (const [key] of files) swift += `        case "${key}": return ${ident(key)}\n`;
swift += "        default: return nil\n";
swift += "        }\n";
swift += "    }\n\n";
for (const [key, file] of files) {
  const json = readFileSync(join(tests, file), "utf8");
  swift += `    static let ${ident(key)} = "${escapeSwift(json)}"\n`;
}
swift += "}\n";

writeFileSync(join(tests, "VectorData.swift"), swift, "utf8");
console.log("OK -> app/Tests/VectorData.swift");