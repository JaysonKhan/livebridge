#!/usr/bin/env bash
# Builds and runs the core tests with the system compiler (no CMake needed). CI uses CMake + CTest instead.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
c++ -std=c++17 -O1 -Wall -Wextra -pthread -Iinclude src/*.cpp tests/core_tests.cpp -o "$OUT/core_tests"
"$OUT/core_tests" ../../../../packages/protocol/fixtures/frames.json
