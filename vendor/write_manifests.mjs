// Generates the vendored-asset manifest, the Full module allowlist, and the
// third-party notices file from whatever scripts/vendor_web_assets.sh emitted.
//
// Every shipped file is hashed so packaging audits and reviewers can confirm
// exactly which bytes are inside each edition.

import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, posix, relative, sep } from "node:path";

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;
    values[token.slice(2)] = argv[index + 1];
    index += 1;
  }
  return values;
}

const args = parseArguments(process.argv.slice(2));
const repoRoot = args.repo;
if (!repoRoot) {
  console.error("--repo is required");
  process.exit(1);
}

const resourcesDir = join(repoRoot, "MDViewerPlus", "Resources");

function listFiles(directory) {
  const results = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true }).sort((a, b) =>
      a.name < b.name ? -1 : a.name > b.name ? 1 : 0
    )) {
      const absolute = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(absolute);
      } else if (entry.isFile()) {
        results.push(absolute);
      }
    }
  };
  walk(directory);
  return results;
}

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function relativePosix(file) {
  return relative(resourcesDir, file).split(sep).join(posix.sep);
}

const packages = [
  {
    name: "marked",
    version: args["marked-version"],
    license: "MIT",
    source: "https://registry.npmjs.org/marked/-/marked-{version}.tgz",
    homepage: "https://github.com/markedjs/marked",
    purpose: "Markdown to HTML parsing",
    edition: "common",
    files: ["Common/marked.min.js"],
    provenance: "upstream minified distribution, copied verbatim",
  },
  {
    name: "dompurify",
    version: args["dompurify-version"],
    license: "Apache-2.0 OR MPL-2.0",
    source: "https://registry.npmjs.org/dompurify/-/dompurify-{version}.tgz",
    homepage: "https://github.com/cure53/DOMPurify",
    purpose: "HTML and SVG sanitization",
    edition: "common",
    files: ["Common/dompurify.min.js"],
    provenance: "upstream minified distribution, copied verbatim",
  },
  {
    name: "marked-footnote",
    version: args["marked-footnote-version"],
    license: "MIT",
    source:
      "https://registry.npmjs.org/marked-footnote/-/marked-footnote-{version}.tgz",
    homepage: "https://github.com/bent10/marked-extensions",
    purpose: "Markdown footnote syntax for preview and print",
    edition: "common",
    files: ["Common/marked-footnote.min.js"],
    provenance:
      "bundled from the upstream ESM entry with esbuild {esbuild} (iife, minified)",
  },
  {
    name: "prismjs",
    version: args["prism-version"],
    license: "MIT",
    source: "https://registry.npmjs.org/prismjs/-/prismjs-{version}.tgz",
    homepage: "https://github.com/PrismJS/prism",
    purpose:
      "Lite preview code highlighting for swift, javascript, typescript, json, bash, python, rust, html, css",
    edition: "lite",
    files: ["Lite/prism-lite.min.js"],
    provenance:
      "custom build: components/prism-core plus the listed languages concatenated in dependency order and minified with esbuild {esbuild}",
  },
  {
    name: "highlight.js",
    version: args["highlight-version"],
    license: "BSD-3-Clause",
    source:
      "https://registry.npmjs.org/highlight.js/-/highlight.js-{version}.tgz",
    homepage: "https://github.com/highlightjs/highlight.js",
    purpose: "Full preview code highlighting across the common language set",
    edition: "full",
    files: ["Full/modules/highlight.esm.min.mjs"],
    provenance:
      "bundled from highlight.js/lib/common with esbuild {esbuild} (esm, minified)",
  },
  {
    name: "js-yaml",
    version: args["js-yaml-version"],
    license: "MIT",
    source: "https://registry.npmjs.org/js-yaml/-/js-yaml-{version}.tgz",
    homepage: "https://github.com/nodeca/js-yaml",
    purpose: "Full YAML frontmatter parsing with the failsafe schema",
    edition: "full",
    files: ["Full/modules/js-yaml.esm.min.mjs"],
    provenance:
      "bundled from the load/FAILSAFE_SCHEMA surface with esbuild {esbuild} (esm, minified)",
  },
  {
    name: "svg-pan-zoom",
    version: args["svg-pan-zoom-version"],
    license: "BSD-2-Clause",
    source:
      "https://registry.npmjs.org/svg-pan-zoom/-/svg-pan-zoom-{version}.tgz",
    homepage: "https://github.com/bumbu/svg-pan-zoom",
    purpose: "Full diagram pan and zoom after a diagram has rendered",
    edition: "full",
    files: ["Full/modules/svg-pan-zoom.esm.min.mjs"],
    provenance:
      "bundled from the upstream UMD distribution with esbuild {esbuild} (esm, minified)",
  },
  {
    name: "mermaid",
    version: args["mermaid-version"],
    license: "MIT",
    source: "https://registry.npmjs.org/mermaid/-/mermaid-{version}.tgz",
    homepage: "https://github.com/mermaid-js/mermaid",
    purpose: "Full offline diagram rendering for every supported diagram family",
    edition: "full",
    files: ["Full/modules/mermaid/**"],
    provenance:
      "official modular ESM distribution (dist/mermaid.esm.min.mjs and dist/chunks/mermaid.esm.min) copied verbatim without source maps",
  },
];

const editionOf = (relativePath) => {
  if (relativePath.startsWith("Common/")) return "common";
  if (relativePath.startsWith("Lite/")) return "lite";
  if (relativePath.startsWith("Full/")) return "full";
  return "app";
};

const shippedFiles = [];
for (const directory of ["Common", "Lite", "Full"]) {
  const absolute = join(resourcesDir, directory);
  let exists = true;
  try {
    statSync(absolute);
  } catch {
    exists = false;
  }
  if (!exists) continue;
  for (const file of listFiles(absolute)) {
    const relativePath = relativePosix(file);
    shippedFiles.push({
      path: relativePath,
      edition: editionOf(relativePath),
      bytes: statSync(file).size,
      sha256: sha256(file),
    });
  }
}

const totals = {};
for (const file of shippedFiles) {
  totals[file.edition] = (totals[file.edition] ?? 0) + file.bytes;
}

const resolvedPackages = packages.map((entry) => ({
  ...entry,
  source: entry.source.replace("{version}", entry.version),
  provenance: entry.provenance.replace("{esbuild}", args["esbuild-version"]),
}));

const manifest = {
  $comment:
    "Generated by scripts/vendor_web_assets.sh. Do not edit by hand; rerun the script instead.",
  generator: {
    script: "scripts/vendor_web_assets.sh",
    esbuild: args["esbuild-version"],
  },
  packages: resolvedPackages,
  files: shippedFiles,
  totals,
};

writeFileSync(
  join(repoRoot, "vendor", "manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`
);

// Allowlist consumed by the bundle-only module scheme handler. Only files
// listed here can ever be served to the preview, and only from the app bundle.
const moduleAllowlist = shippedFiles
  .filter((file) => file.path.startsWith("Full/modules/"))
  .map((file) => ({
    path: file.path.slice("Full/modules/".length),
    sha256: file.sha256,
    bytes: file.bytes,
  }));

writeFileSync(
  join(resourcesDir, "Full", "module-allowlist.json"),
  `${JSON.stringify(
    {
      $comment:
        "Generated by scripts/vendor_web_assets.sh. Every path the Full module scheme handler may serve, relative to Resources/Full/modules.",
      modules: moduleAllowlist,
    },
    null,
    2
  )}\n`
);

const kilobytes = (bytes) => `${(bytes / 1024).toFixed(1)} KB`;

const notices = [];
notices.push("# Third-Party Notices");
notices.push("");
notices.push(
  "MDViewer+ bundles the web assets below inside the application bundle. Nothing is fetched at runtime; the app never opens a network connection for rendering."
);
notices.push("");
notices.push(
  "This file is generated by `scripts/vendor_web_assets.sh`. Rerun that script instead of editing it."
);
notices.push("");
notices.push("## Packages");
notices.push("");
notices.push("| Package | Version | License | Edition | Purpose |");
notices.push("| --- | --- | --- | --- | --- |");
for (const entry of resolvedPackages) {
  notices.push(
    `| [${entry.name}](${entry.homepage}) | ${entry.version} | ${entry.license} | ${entry.edition} | ${entry.purpose} |`
  );
}
notices.push("");
notices.push("### Provenance");
notices.push("");
for (const entry of resolvedPackages) {
  notices.push(`- **${entry.name} ${entry.version}** — ${entry.provenance}`);
  notices.push(`  - Source: \`${entry.source}\``);
}
notices.push("");
notices.push("## Shipped files and checksums");
notices.push("");
notices.push("| Edition | Size | Files |");
notices.push("| --- | --- | --- |");
for (const edition of ["common", "lite", "full"]) {
  const files = shippedFiles.filter((file) => file.edition === edition);
  notices.push(
    `| ${edition} | ${kilobytes(totals[edition] ?? 0)} | ${files.length} |`
  );
}
notices.push("");
notices.push(
  "Per-file SHA-256 checksums are recorded in `vendor/manifest.json`. `scripts/audit_bundle.sh` verifies a built app bundle against that manifest, including proof that Lite contains no Full asset."
);
notices.push("");
notices.push("### Individually listed files");
notices.push("");
notices.push("| File | Edition | Bytes | SHA-256 |");
notices.push("| --- | --- | --- | --- |");
for (const file of shippedFiles) {
  if (file.path.startsWith("Full/modules/mermaid/chunks/")) continue;
  notices.push(
    `| \`${file.path}\` | ${file.edition} | ${file.bytes} | \`${file.sha256}\` |`
  );
}
notices.push("");
const mermaidChunks = shippedFiles.filter((file) =>
  file.path.startsWith("Full/modules/mermaid/chunks/")
);
notices.push(
  `Mermaid additionally ships ${mermaidChunks.length} diagram chunks totalling ${kilobytes(
    mermaidChunks.reduce((sum, file) => sum + file.bytes, 0)
  )} under \`Full/modules/mermaid/chunks/mermaid.esm.min/\`. Their checksums are in \`vendor/manifest.json\`.`
);
notices.push("");
notices.push("## License texts");
notices.push("");
notices.push(
  "Full license texts ship inside the app bundle next to the code they cover:"
);
notices.push("");
for (const file of shippedFiles.filter((file) =>
  /LICENSE|NOTICES/.test(file.path)
)) {
  notices.push(`- \`Resources/${file.path}\``);
}
notices.push("");

writeFileSync(
  join(repoRoot, "THIRD-PARTY-NOTICES.md"),
  `${notices.join("\n")}`
);

console.log(
  `  manifest.json: ${shippedFiles.length} files, ${resolvedPackages.length} packages`
);
console.log(`  module allowlist: ${moduleAllowlist.length} modules`);
for (const edition of ["common", "lite", "full"]) {
  console.log(`  ${edition}: ${kilobytes(totals[edition] ?? 0)}`);
}
