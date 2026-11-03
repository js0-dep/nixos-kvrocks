#!/usr/bin/env python3

import os
import sys
import shutil
import subprocess
import re
import json
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed


def parse_cmake_file(path: Path):
    content = path.read_text(encoding="utf-8", errors="replace")

    # Pattern for FetchContent_DeclareGitHubWithMirror
    match = re.search(
        r"FetchContent_DeclareGitHubWithMirror\s*\(\s*(\S+)\s+([\w.-]+)/([\w.-]+)\s+([\w.-]+)",
        content,
    )
    if match:
        _, owner, repo, rev = match.groups()
        return path.stem, {"owner": owner, "repo": repo, "rev": rev}

    # Pattern for FetchContent_DeclareGitHubTarWithMirror
    match = re.search(
        r"FetchContent_DeclareGitHubTarWithMirror\s*\(\s*(\S+)\s+([\w.-]+)/([\w.-]+)\s+([\w.-]+)",
        content,
    )
    if match:
        _, owner, repo, rev = match.groups()
        return path.stem, {"owner": owner, "repo": repo, "rev": rev}

    return None, None


def generate_dep_json(cmake_dir: Path, output_path: Path):
    deps = {}
    ignore_list = {"riscv64.cmake"}

    if not cmake_dir.exists():
        print(f"❌ CMake directory not found: {cmake_dir}", file=sys.stderr)
        return deps

    print(f"🔍 Scanning {cmake_dir}...")
    for fname in sorted(os.listdir(cmake_dir)):
        if fname.endswith(".cmake") and fname not in ignore_list:
            path = cmake_dir / fname
            key, dep_info = parse_cmake_file(path)
            if key and dep_info:
                print(f"  -> Found {key} ({dep_info['owner']}/{dep_info['repo']} @ {dep_info['rev']})")
                deps[key] = dep_info

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(deps, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"✅ Generated {output_path}")
    return deps


def resolve_commit_sha(name: str, owner: str, repo: str, rev: str) -> str:
    if re.fullmatch(r"[0-9a-f]{40}", rev):
        return rev

    url = f"https://github.com/{owner}/{repo}"
    try:
        result = subprocess.run(
            ["git", "ls-remote", url, rev],
            capture_output=True,
            text=True,
            check=True,
            encoding="utf-8",
            timeout=30,
        )
        lines = result.stdout.strip().splitlines()
        if lines:
            return lines[0].split()[0]
    except Exception as e:
        print(f"  ⚠️  Failed to resolve {name} commit SHA for {rev}: {e}", file=sys.stderr)

    return rev


def prefetch_hash(name: str, owner: str, repo: str, commit_hash: str) -> str:
    url = f"https://github.com/{owner}/{repo}/archive/{commit_hash}.tar.gz"

    if not shutil.which("nix-prefetch-url"):
        raise RuntimeError("`nix-prefetch-url` command not found in PATH")

    # Fetch hash using nix-prefetch-url
    result = subprocess.run(
        [
            "nix-prefetch-url",
            "--unpack",
            "--type",
            "sha256",
            url,
        ],
        capture_output=True,
        text=True,
        check=True,
        encoding="utf-8",
        timeout=120,
    )
    raw_hash = result.stdout.strip().split("\n")[-1]

    # Convert to SRI format using `nix hash to-sri`
    convert_result = subprocess.run(
        ["nix", "hash", "to-sri", "--type", "sha256", raw_hash],
        capture_output=True,
        text=True,
        check=True,
        encoding="utf-8",
        timeout=30,
    )
    return convert_result.stdout.strip()


def process_dep(name: str, info: dict, cached_sha: dict):
    owner, repo, rev = info["owner"], info["repo"], info["rev"]

    # Reuse cached hash if rev matches
    if name in cached_sha and cached_sha[name].get("rev") == rev:
        return name, cached_sha[name], True

    # Resolve commit SHA if needed
    commit_sha = resolve_commit_sha(name, owner, repo, rev)

    # Prefetch SRI hash
    try:
        sri_hash = prefetch_hash(name, owner, repo, commit_sha)
        return (
            name,
            {
                "rev": rev,
                "commit": commit_sha,
                "hash": sri_hash,
            },
            False,
        )
    except Exception as e:
        print(f"  ❌ Failed to prefetch {name} ({owner}/{repo}): {e}", file=sys.stderr)
        if name in cached_sha:
            print(f"  ⚠️  Keeping previously cached value for {name}")
            return name, cached_sha[name], True
        return name, None, False


def generate_sha_json(deps: dict, output_path: Path, max_workers: int = 8):
    existing_sha = {}
    if output_path.exists():
        try:
            with open(output_path, "r", encoding="utf-8") as f:
                existing_sha = json.load(f)
            print(f"📖 Loaded existing {output_path} ({len(existing_sha)} entries)")
        except (json.JSONDecodeError, IOError) as e:
            print(f"⚠️  Could not load existing {output_path}: {e}")

    sha = {}
    print(f"\n🚀 Resolving commit SHAs and prefetching sources (max {max_workers} threads)...")

    has_nix_prefetch = shutil.which("nix-prefetch-url") is not None
    if not has_nix_prefetch:
        print("⚠️  `nix-prefetch-url` not available in PATH; reusing cached hashes where possible.")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_name = {
            executor.submit(process_dep, name, info, existing_sha): name
            for name, info in deps.items()
        }

        for future in as_completed(future_to_name):
            name, data, is_cached = future.result()
            if data:
                sha[name] = data
                status = "⚡ Cached" if is_cached else "✨ Updated"
                print(f"  [{status}] {name} @ {data['rev']} ({data['commit'][:7]})")
            else:
                print(f"  [❌ Failed] {name}")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(sha, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"✅ Generated {output_path} ({len(sha)} entries)")


def main():
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir / "kvrocks"
    cmake_dir = project_root / "cmake"
    dep_json_path = script_dir / "dep.json"
    sha_json_path = script_dir / "sha.json"

    print("=== Generating dependency metadata ===")
    deps = generate_dep_json(cmake_dir, dep_json_path)

    print("\n=== Generating hash metadata ===")
    generate_sha_json(deps, sha_json_path)

    print("\n🎉 Done!")


if __name__ == "__main__":
    main()
