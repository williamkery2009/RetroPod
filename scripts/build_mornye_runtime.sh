#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/prepare_mornye_runtime.sh"
cd "$ROOT/build/mornye-source/rust_backend"
export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to the Android NDK}"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 --platform 23 -o "$ROOT/android/app/src/main/jniLibs" build --release -p retropod-extensions
