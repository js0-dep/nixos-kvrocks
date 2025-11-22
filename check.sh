#!/usr/bin/env bash

set -e
DIR=$(realpath $0) && DIR=${DIR%/*}
cd $DIR
set -x

export NIX_CONFIG="extra-experimental-features = nix-command flakes"
exec nix flake check path:. --no-build --all-systems
