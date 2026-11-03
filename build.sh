#!/usr/bin/env bash

set -euo pipefail
DIR=$(realpath "$0") && DIR=${DIR%/*}
cd "$DIR"

if ! command -v nix &>/dev/null; then
  echo "❌ Nix is not installed."
  if command -v brew &>/dev/null; then
    echo "Attempting to install via brew..."
    brew install nix
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y nix
  else
    echo "Please install Nix from https://nixos.org/download.html"
    exit 1
  fi
fi

echo "🔨 Building kvrocks..."
rm -f result
exec nix build .#default --print-build-logs --extra-experimental-features "nix-command flakes" "$@"
