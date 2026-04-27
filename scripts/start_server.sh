#!/usr/bin/env bash
# start_server.sh — Start the llama-grpc-server
#
# Usage:
#   bash scripts/start_server.sh [model_path] [port]
#
# Examples:
#   bash scripts/start_server.sh
#   bash scripts/start_server.sh models/phi-3.5-mini.gguf
#   bash scripts/start_server.sh models/llama3.2-3b.gguf 50052
#
# Environment variables (override positional args):
#   LLAMA_MODEL_PATH   Path to GGUF model file
#   LLAMA_PORT         Port to listen on (default: 50051)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$REPO_ROOT/build/llama-grpc-server"

info()    { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
error()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
die()     { error "$*"; exit 1; }

# ─── resolve model path ──────────────────────────────────────────────────────
MODEL_PATH="${1:-${LLAMA_MODEL_PATH:-}}"
PORT="${2:-${LLAMA_PORT:-50051}}"

if [[ -z "$MODEL_PATH" ]]; then
    # Auto-discover: pick the first .gguf in the models/ directory
    MODELS_DIR="$REPO_ROOT/models"
    if [[ -d "$MODELS_DIR" ]]; then
        MODEL_PATH="$(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf' | sort | head -1)"
    fi
fi

[[ -n "$MODEL_PATH" ]] || \
    die "No model specified and none found in models/. Pass a .gguf path as the first argument."

[[ -f "$MODEL_PATH" ]] || \
    die "Model file not found: $MODEL_PATH"

# ─── check binary ────────────────────────────────────────────────────────────
if [[ ! -x "$BINARY" ]]; then
    die "Server binary not found at $BINARY. Run ./install.sh first."
fi

# ─── start ───────────────────────────────────────────────────────────────────
info "Model:  $MODEL_PATH"
info "Port:   $PORT"
info "Binary: $BINARY"
echo ""

exec "$BINARY" "$MODEL_PATH" "$PORT"
