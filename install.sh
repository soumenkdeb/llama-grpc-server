#!/usr/bin/env bash
# install.sh — llama-grpc-server installer
#
# Supported platforms: Linux (x86_64, aarch64)
# Package managers:    apt (Debian/Ubuntu), pacman (Arch/CachyOS),
#                      dnf/yum (Fedora/RHEL/CentOS), slackpkg (Slackware)
#
# Privilege policy:
#   Package installation always requires root (via sudo or running as root).
#   Binary installation (INSTALL_SYSTEM=1) uses elevated privileges only when
#   the target directory is not writable by the current user — completely
#   silent when it is (e.g. ~/.local/bin or running as root in a container).

set -euo pipefail

# ─── defaults ────────────────────────────────────────────────────────────────
INSTALL_PREFIX="${PREFIX:-/usr/local}"
ENABLE_VULKAN=1
BUILD_DIR="build"
MODELS_DIR="models"
SERVICE_NAME="llama-grpc-server"

# ─── helpers ─────────────────────────────────────────────────────────────────
info()    { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
success() { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn()    { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error()   { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
die()     { error "$*"; exit 1; }

# Run a command with elevated privileges only when needed.
# - Already root → run directly (no sudo prompt)
# - sudo available → use it (will prompt once for the session)
# - Neither       → warn and attempt anyway (might be a rootless container)
maybe_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        warn "Not running as root and 'sudo' not found — attempting without elevated privileges."
        "$@"
    fi
}

usage() {
    cat <<EOF
llama-grpc-server installer

Usage:
  bash install.sh [options]

Options:
  --no-vulkan          Build CPU-only (skip the Vulkan GPU backend)
  --prefix PATH        Installation prefix used when INSTALL_SYSTEM=1
                       (default: /usr/local)
  -h, --help           Show this help and exit

Environment variables:
  PREFIX               Equivalent to --prefix PATH
  INSTALL_SYSTEM=1     Copy the built binary to PREFIX/bin after a successful
                       build; elevated privileges are used only when the target
                       directory is not writable by the current user

Privilege behaviour:
  Package installation always requires root (sudo or already running as root).
  Binary installation (INSTALL_SYSTEM=1) silently skips sudo when the target
  directory is already writable — e.g. ~/.local/bin or a container root shell.
  Specify --prefix ~/.local to install without any sudo prompt at all.

Supported package managers:
  apt        Debian, Ubuntu, and derivatives
  pacman     Arch Linux, CachyOS, Manjaro, and derivatives
  dnf / yum  Fedora, RHEL, CentOS, Rocky Linux, AlmaLinux
  slackpkg   Slackware — installs base packages from official tree;
             gRPC and Protobuf must be built from SlackBuilds.org (sbopkg)

What this script does:
  1. Detects your package manager and installs missing build dependencies
  2. Verifies that CMake >= 3.22 is available
  3. Initialises the llama.cpp git submodule (--recursive)
  4. Configures and builds the server into ./build/
  5. Creates ./models/ with download instructions if it does not yet exist
  6. Optionally installs the binary system-wide when INSTALL_SYSTEM=1

Examples:
  bash install.sh                          # Vulkan GPU build (auto-detect deps)
  bash install.sh --no-vulkan              # CPU-only build
  bash install.sh --prefix ~/.local        # user-local install (no sudo needed)
  INSTALL_SYSTEM=1 bash install.sh         # build + install to /usr/local/bin
  INSTALL_SYSTEM=1 bash install.sh --prefix ~/.local --no-vulkan

After a successful build:
  Start the server:
    ./build/llama-grpc-server <path/to/model.gguf> [port]

  Or use the helper script (auto-discovers models/ directory):
    bash scripts/start_server.sh [path/to/model.gguf] [port]

  Python interactive client (multi-turn):
    cd llama-grpc-py-client && python interactive.py [--host HOST] [--port PORT]

  Python one-shot client:
    cd llama-grpc-py-client && python client.py "Your question here"

EOF
}

# ─── parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-vulkan)   ENABLE_VULKAN=0 ;;
        --prefix)      INSTALL_PREFIX="$2"; shift ;;
        --prefix=*)    INSTALL_PREFIX="${1#*=}" ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "Unknown option: $1" ;;
    esac
    shift
done

# ─── detect OS ───────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
[[ "$OS" == "Linux" ]] || die "Only Linux is supported at this time."
info "Platform: $OS $ARCH"

# ─── package manager detection and dependency installation ────────────────────

install_deps_apt() {
    info "Updating package lists (apt)..."
    maybe_sudo apt-get update -qq
    info "Installing build dependencies via apt..."
    maybe_sudo apt-get install -y --no-install-recommends \
        build-essential cmake git pkg-config \
        libgrpc++-dev libprotobuf-dev protobuf-compiler \
        protobuf-compiler-grpc
    if [[ "$ENABLE_VULKAN" -eq 1 ]]; then
        maybe_sudo apt-get install -y --no-install-recommends \
            libvulkan-dev glslc \
        || warn "Vulkan dev packages not found — disabling Vulkan backend."
    fi
}

install_deps_pacman() {
    info "Syncing package databases (pacman)..."
    maybe_sudo pacman -Sy --noconfirm
    info "Installing build dependencies via pacman..."
    maybe_sudo pacman -S --needed --noconfirm \
        base-devel cmake git \
        grpc protobuf
    if [[ "$ENABLE_VULKAN" -eq 1 ]]; then
        maybe_sudo pacman -S --needed --noconfirm \
            vulkan-headers shaderc \
        || warn "Vulkan dev packages not found — disabling Vulkan backend."
    fi
}

install_deps_dnf() {
    local PKG_MGR="dnf"
    command -v dnf &>/dev/null || PKG_MGR="yum"
    info "Refreshing package metadata ($PKG_MGR)..."
    maybe_sudo "$PKG_MGR" makecache --quiet
    info "Installing build dependencies via $PKG_MGR..."
    maybe_sudo "$PKG_MGR" install -y \
        gcc-c++ cmake git pkgconfig \
        grpc-devel grpc-plugins \
        protobuf-devel protobuf-compiler
    if [[ "$ENABLE_VULKAN" -eq 1 ]]; then
        maybe_sudo "$PKG_MGR" install -y \
            vulkan-headers glslc \
        || warn "Vulkan dev packages not found — disabling Vulkan backend."
    fi
}

install_deps_slackware() {
    info "Updating slackpkg database..."
    maybe_sudo slackpkg update
    info "Installing available base dependencies via slackpkg..."
    # Only cmake and git are reliably available in the official Slackware tree.
    # gcc and pkg-config ship with a standard Slackware installation.
    maybe_sudo slackpkg install cmake git || true

    warn "─────────────────────────────────────────────────────────"
    warn "gRPC and Protobuf are NOT in the official Slackware repos."
    warn "They must be built from SlackBuilds.org (https://slackbuilds.org)."
    if command -v sbopkg &>/dev/null; then
        warn "sbopkg is installed. To build the required packages run:"
        warn "  sudo sbopkg -i protobuf"
        warn "  sudo sbopkg -i grpc"
        if [[ "$ENABLE_VULKAN" -eq 1 ]]; then
            warn "  sudo sbopkg -i vulkan-sdk"
            warn "  sudo sbopkg -i shaderc"
        fi
        warn "Then re-run this installer."
    else
        warn "sbopkg not found. Install it from https://sbopkg.org, then run:"
        warn "  sudo sbopkg -i protobuf && sudo sbopkg -i grpc"
        if [[ "$ENABLE_VULKAN" -eq 1 ]]; then
            warn "  sudo sbopkg -i vulkan-sdk && sudo sbopkg -i shaderc"
        fi
        warn "Then re-run this installer."
    fi
    warn "─────────────────────────────────────────────────────────"
    warn "Continuing build — it will fail if gRPC/Protobuf are not installed."
}

if   command -v apt-get  &>/dev/null; then install_deps_apt
elif command -v pacman   &>/dev/null; then install_deps_pacman
elif command -v dnf      &>/dev/null || \
     command -v yum      &>/dev/null; then install_deps_dnf
elif command -v slackpkg &>/dev/null; then install_deps_slackware
else
    warn "Unknown package manager — skipping automatic dependency install."
    warn "Ensure cmake>=3.22, gRPC, Protobuf, and (optionally) Vulkan SDK are installed."
fi

# ─── verify cmake version ────────────────────────────────────────────────────
CMAKE_VER=$(cmake --version 2>/dev/null | head -1 | awk '{print $3}')
CMAKE_MAJOR=$(echo "$CMAKE_VER" | cut -d. -f1)
CMAKE_MINOR=$(echo "$CMAKE_VER" | cut -d. -f2)
if [[ "$CMAKE_MAJOR" -lt 3 ]] || { [[ "$CMAKE_MAJOR" -eq 3 ]] && [[ "$CMAKE_MINOR" -lt 22 ]]; }; then
    die "CMake >= 3.22 required (found $CMAKE_VER)"
fi
info "CMake $CMAKE_VER"

# ─── initialise submodules ───────────────────────────────────────────────────
info "Initialising llama.cpp submodule..."
git submodule update --init --recursive

# ─── build ───────────────────────────────────────────────────────────────────
NPROC=$(nproc 2>/dev/null || echo 4)

CMAKE_EXTRA_ARGS=()
if [[ "$ENABLE_VULKAN" -eq 0 ]]; then
    CMAKE_EXTRA_ARGS+=(-DGGML_VULKAN=OFF)
    info "Vulkan backend: disabled"
else
    info "Vulkan backend: enabled (pass --no-vulkan to disable)"
fi

info "Configuring build in ./$BUILD_DIR ..."
cmake -S . -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    "${CMAKE_EXTRA_ARGS[@]}"

info "Building with $NPROC parallel jobs..."
cmake --build "$BUILD_DIR" --config Release --parallel "$NPROC"

success "Build complete: $BUILD_DIR/$SERVICE_NAME"

# ─── models directory ────────────────────────────────────────────────────────
if [[ ! -d "$MODELS_DIR" ]]; then
    info "Creating models directory: $MODELS_DIR/"
    mkdir -p "$MODELS_DIR"
    info "Download a GGUF model from Hugging Face and place it in ./$MODELS_DIR/"
    info "Example (Llama 3.2 3B Q4):"
    info "  huggingface-cli download bartowski/Llama-3.2-3B-Instruct-GGUF \\"
    info "    Llama-3.2-3B-Instruct-Q4_K_M.gguf --local-dir ./$MODELS_DIR"
fi

# ─── optional system-wide install ────────────────────────────────────────────
if [[ "${INSTALL_SYSTEM:-0}" -eq 1 ]]; then
    DEST_DIR="$INSTALL_PREFIX/bin"
    DEST="$DEST_DIR/$SERVICE_NAME"
    info "Installing binary to $DEST ..."

    # Create destination directory without elevated privileges if possible.
    if [[ ! -d "$DEST_DIR" ]]; then
        if ! mkdir -p "$DEST_DIR" 2>/dev/null; then
            maybe_sudo mkdir -p "$DEST_DIR"
        fi
    fi

    # Copy the binary — only elevate when the directory is not writable.
    if [[ -w "$DEST_DIR" ]]; then
        install -Dm755 "$BUILD_DIR/$SERVICE_NAME" "$DEST"
    else
        maybe_sudo install -Dm755 "$BUILD_DIR/$SERVICE_NAME" "$DEST"
    fi

    success "Installed to $DEST"
fi

# ─── summary ─────────────────────────────────────────────────────────────────
echo ""
success "Installation complete!"
echo ""
echo "  Start the server:"
echo "    ./$BUILD_DIR/$SERVICE_NAME <path/to/model.gguf>"
echo ""
echo "  Or use the helper script:"
echo "    bash scripts/start_server.sh <path/to/model.gguf>"
echo ""
echo "  Python client (from llama-grpc-py-client/):"
echo "    python interactive.py"
echo ""
