#!/usr/bin/env python3

import shutil
import subprocess
from pathlib import Path


def main():
    root_dir = Path(__file__).parent.resolve()
    dest_dir = root_dir / "nixpkgs/pkgs/by-name/kv/kvrocks"

    dest_dir.mkdir(parents=True, exist_ok=True)

    # Copy metadata and package files
    for filename in ["dep.json", "ver.json", "sha.json", "package.nix"]:
        src = root_dir / filename
        dst = dest_dir / filename
        shutil.copy2(src, dst)
        print(f"Copied {filename} -> {dest_dir}")

    # Format if nixpkgs repo is checked out
    nixpkgs_dir = root_dir / "nixpkgs"
    if (nixpkgs_dir / ".git").exists():
        try:
            print("Running nix fmt in nixpkgs...")
            subprocess.run(["nix", "fmt"], cwd=nixpkgs_dir, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"Note: nix fmt skipped: {e}")

    print("Done.")


if __name__ == "__main__":
    main()
