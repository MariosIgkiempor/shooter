#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build

echo "== Building atlas =="
odin run vendor/atlas-builder -out:build/atlas-builder.bin

echo "== Building maps =="
odin run vendor/map-builder -out:build/map-builder.bin

echo "== Building and running game =="
odin run . -out:build/shooter.bin
