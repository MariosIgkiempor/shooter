#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "== Building atlas =="
odin run vendor/atlas-builder -out:atlas-builder.bin

echo "== Building and running game =="
odin run . -out:shooter.bin
