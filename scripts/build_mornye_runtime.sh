#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/prepare_mornye_runtime.sh"
cd "$ROOT/build/mornye-source/rust_backend"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -p 23 -o "$ROOT/android/app/src/main/jniLibs" build --release -p retropod-extensions
