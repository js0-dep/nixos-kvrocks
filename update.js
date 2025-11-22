#!/usr/bin/env bun

import verJson from "@3-/nix/verJson.js";
import { cd, $ } from "zx";

const ROOT = import.meta.dirname;
cd(ROOT);

await verJson(ROOT, "apache/kvrocks", process.argv[3]);

await $`./update_dep.py`;

// import { existsSync } from "node:fs";
// if (existsSync("nixpkgs")) {
//   cd("nixpkgs");
//   await $`git pull`;
//   cd("..");
// } else {
//   await $`git clone --depth=1 git@github.com:js0-fork/nixpkgs.git`;
// }
//
// await $`./nixpkg.gen.py`;
