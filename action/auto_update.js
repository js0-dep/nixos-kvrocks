#!/usr/bin/env bun

import reqJson from "@3-/req/reqJson.js";
import ver from "../ver.json";
import { gt } from "semver";
import { $ } from "bun";

const { tag_name } = await reqJson(
  "https://api.github.com/repos/apache/kvrocks/releases/latest",
);
if (gt(tag_name.slice(1), ver.rev.slice(1))) {
  await $`cd .. && bun i && ./update.js && git add -u && git commit -m"${tag_name}"`;
}
