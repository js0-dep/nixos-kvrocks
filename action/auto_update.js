#!/usr/bin/env bun

import reqJson from "@3-/req/reqJson.js";
import ver from "../ver.json";
import semver from "semver";
import { $ } from "bun";

const headers = {
  "User-Agent": "nixos-kvrocks-auto-update",
  ...(process.env.GITHUB_TOKEN ? { Authorization: "Bearer " + process.env.GITHUB_TOKEN } : {})
};

console.log(`Current local version: ${ver.rev}`);
const release = await reqJson(
  "https://api.github.com/repos/apache/kvrocks/releases/latest",
  { headers }
);

const upstreamTag = release.tag_name;
console.log(`Upstream latest release: ${upstreamTag}`);

const localVer = semver.clean(ver.rev) || semver.coerce(ver.rev);
const upstreamVer = semver.clean(upstreamTag) || semver.coerce(upstreamTag);

if (upstreamVer && localVer && semver.gt(upstreamVer, localVer)) {
  console.log(`🚀 New version detected: ${upstreamTag} > ${ver.rev}`);
  await $`cd .. && bun i && ./update.js ${upstreamTag}`;
  await $`cd .. && git add ver.json dep.json sha.json package.nix flake.nix`;
  await $`cd .. && git commit -m "chore(release): update to kvrocks ${upstreamTag}"`;
  
  if (process.env.GITHUB_ENV) {
    await $`echo "RELEASE_TAG=${upstreamTag}" >> ${process.env.GITHUB_ENV}`;
  }
} else {
  console.log(`✅ Already up to date (${ver.rev})`);
}
