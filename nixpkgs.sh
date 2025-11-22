#!/usr/bin/env bash

set -e
DIR=$(realpath $0) && DIR=${DIR%/*}
cd $DIR
set -x

if [ -d nixpkgs ]; then
  cd nixpkgs
  git pull
else
  git clone --depth=1 git@github.com:js0-fork/nixpkgs.git
fi
