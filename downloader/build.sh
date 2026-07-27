#!/usr/bin/env bash
# Build Convoy templates downloader from this source tree (no GitHub release binary).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v cargo >/dev/null 2>&1; then
  echo "→ Installing Rust toolchain (rustup)…"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi

echo "→ Building release binary…"
cargo build --release

BIN="$ROOT/target/release/downloader"
chmod +x "$BIN"
echo "✓ Built: $BIN"
echo "$BIN"
