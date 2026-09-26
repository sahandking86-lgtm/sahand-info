#!/usr/bin/env bash
#
# Downloads the offline GGUF model into Resources/model.gguf.
#
# Used by:
#   • local setup — run this once before the first `xcodegen generate` + build
#   • .github/workflows/build.yml — same step, so CI and local stay identical
#
# What it does nothing about: git. The model is ~2 GB and is .gitignored on purpose.
#
# Usage:
#   ./scripts/fetch-model.sh
#   MODEL_URL=https://example.com/some-model.gguf ./scripts/fetch-model.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${MODEL_DIR:-$REPO_ROOT/Resources}"
MODEL_FILE="${MODEL_FILE:-model.gguf}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf}"

DEST="$MODEL_DIR/$MODEL_FILE"

# Sources/LocalAI.swift loads the bundle resource named "model.gguf"; a different
# filename silently turns Offline AI into "Model file missing from app bundle."
if [[ "$MODEL_FILE" != "model.gguf" ]]; then
  echo "warning: Offline AI loads the bundle resource 'model', extension 'gguf'." >&2
  echo "         Keeping the default name avoids a confusing runtime error." >&2
fi

if [[ -s "$DEST" ]]; then
  echo "✓ already there: $DEST ($(du -h "$DEST" | cut -f1)) — nothing to do"
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

mkdir -p "$MODEL_DIR"
echo "→ downloading ${MODEL_URL##*/}"
echo "  into $DEST (~2 GB, one time, resumable)"

# -C -/continue so an interrupted run resumes instead of starting over.
curl -fL --retry 5 --retry-delay 3 -C - --progress-bar -o "$DEST.part" "$MODEL_URL"

# A failed CDN/HTML page would otherwise be packaged as a "model" and only blow up
# inside llama.cpp at runtime, which is a much worse error to debug.
if [[ "$(head -c 4 "$DEST.part" 2>/dev/null || true)" != "GGUF" ]]; then
  rm -f "$DEST.part"
  echo "error: downloaded file is not a GGUF model (bad magic bytes). URL: $MODEL_URL" >&2
  exit 1
fi

mv "$DEST.part" "$DEST"
ls -lh "$DEST"
echo "✓ done — rebuild (xcodegen generate && build) so the model is copied into the app bundle"
