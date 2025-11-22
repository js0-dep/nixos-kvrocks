#!/usr/bin/env bash

set -e
DIR=$(realpath $0) && DIR=${DIR%/*}
cd $DIR
set -x

if ! command -v nix &>/dev/null; then
  echo "Nix is not installed. Installing..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y nix
  elif command -v brew &>/dev/null; then
    brew install nix
  else
    echo "Error: Please install nix manually from https://nixos.org/download.html"
    exit 1
  fi
fi

rm -f result
NIX_ENFORCE_NO_NATIVE=0 nix build --print-build-logs
