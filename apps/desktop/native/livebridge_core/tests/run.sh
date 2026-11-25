#!/usr/bin/env bash
# Builds and runs every tests/*_tests.cpp with the system compiler (no CMake needed). CI uses CMake + CTest.
# Extra compiler flags can be passed, e.g.:  tests/run.sh -fsanitize=address,undefined
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
FIXTURES=../../../../packages/protocol/fixtures/frames.json
for test in tests/*_tests.cpp; do
  name=$(basename "$test" .cpp)
  c++ -std=c++17 -O1 -g -Wall -Wextra -pthread "$@" -Iinclude -Itests src/*.cpp "$test" -o "$OUT/$name"
  printf '%s: ' "$name"
  "$OUT/$name" "$FIXTURES"
done
