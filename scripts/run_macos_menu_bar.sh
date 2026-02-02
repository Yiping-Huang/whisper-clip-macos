#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/macos/WhisperClipMenuBar"

export WHISPER_CLIP_REPO_ROOT="$ROOT_DIR"
export WHISPER_CLIP_PYTHON="${WHISPER_CLIP_PYTHON:-$ROOT_DIR/.venv/bin/python3}"

swift run
