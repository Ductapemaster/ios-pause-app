#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pause-lock-process.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT

mkdir -p "$test_directory/module-cache"
SWIFT_MODULE_CACHE_PATH="$test_directory/module-cache" \
CLANG_MODULE_CACHE_PATH="$test_directory/module-cache" \
xcrun swiftc \
    "$repo_root/Sources/Shared/AppGroupFileLock.swift" \
    "$repo_root/Sources/Shared/SharedIdentifiers.swift" \
    "$script_dir/AppGroupFileLockProcessTest.swift" \
    -o "$test_directory/AppGroupFileLockProcessTest"

"$test_directory/AppGroupFileLockProcessTest" "$test_directory/state"
