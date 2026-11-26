#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/build/mornye-source"
REV=af9a4d6422759541ec57a9ed696b3b47928a1bff
if [ ! -d "$UPSTREAM/.git" ]; then
  git clone https://github.com/mornyeapp/Mornye.git "$UPSTREAM"
fi
git -C "$UPSTREAM" checkout --detach "$REV"
mkdir -p "$UPSTREAM/rust_backend/crates/retropod-extensions"
cp -R "$ROOT/native/mornye_bridge/." "$UPSTREAM/rust_backend/crates/retropod-extensions/"
python3 - "$UPSTREAM/rust_backend/Cargo.toml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
if '"crates/retropod-extensions"' not in s:
    s=s.replace('members = [', 'members = ["crates/retropod-extensions", ')
p.write_text(s)
PY
