#!/usr/bin/env bash

set -euo pipefail
DIR=$(realpath "$0") && DIR=${DIR%/*}
cd "$DIR"

if ! command -v nix &>/dev/null; then
  echo "❌ Nix command not found in PATH."
  exit 1
fi

echo "🔍 Checking Nix flake..."
export NIX_CONFIG="extra-experimental-features = nix-command flakes"
exec nix flake check path:. --no-build --all-systems "$@"
