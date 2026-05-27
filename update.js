#!/usr/bin/env bun

import verJson from "@3-/nix/verJson.js";
import { cd, $ } from "zx";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

const ROOT = import.meta.dirname,
  argv = yargs(hideBin(process.argv))
    .command("$0 <tag>", "Update nixos-kvrocks", (yargs) => {
      yargs.positional("tag", {
        describe: "kvrocks tag to update to",
        type: "string",
      });
    })
    .demandCommand(1)
    .parse();

cd(ROOT);

await verJson(ROOT, "apache/kvrocks", argv.tag);

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
