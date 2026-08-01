#!/bin/sh
# Build sophia-write: Rust core first, then the Swift shell (the shell links
# core/target/release/libsophia_ffi.a). Portable: no absolute paths.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> cargo build --release (core)"
cargo build --release --manifest-path "$ROOT/core/Cargo.toml"

echo "==> swift build -c release (shell)"
swift build -c release --package-path "$ROOT/platform-macos"

echo "==> selftest"
"$ROOT/platform-macos/.build/release/sophia-write" selftest
