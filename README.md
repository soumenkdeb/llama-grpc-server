# llama-grpc-server

A high-performance gRPC server that exposes local LLM inference via a streaming chat API, built on top of [llama.cpp](https://github.com/ggml-org/llama.cpp). Load any GGUF-format model (Llama, Phi, Qwen, Mistral, and more) and interact with it from any gRPC client.

## Features

- Streaming token-by-token responses over gRPC
- Multi-turn conversation with message history
- Per-request sampling parameters (temperature, top-k, top-p, max tokens)
- Vulkan GPU acceleration (optional, falls back to CPU)
- Python clients included: one-shot and interactive
- Compatible with any GGUF model from Hugging Face

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   gRPC Client                       │
│  (Python / any language with gRPC support)          │
└───────────────────┬─────────────────────────────────┘
                    │  ChatCompletion RPC (streaming)
                    │  port 50051 (default)
┌───────────────────▼─────────────────────────────────┐
│              llama-grpc-server (C++)                │
│                                                     │
│   LlamaGrpcService                                  │
│     apply_chat_template()  →  tokenize              │
│     generate_token_stream() →  llama.cpp decode     │
│                             →  stream tokens        │
└───────────────────┬─────────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────────┐
│              llama.cpp (submodule)                  │
│   ggml backend: CPU + Vulkan                        │
│   Model: any GGUF file                              │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

| Dependency | Minimum version | Notes |
|------------|----------------|-------|
| CMake | 3.22 | Build system |
| C++ compiler | GCC 11 / Clang 14 | C++17 required |
| gRPC | 1.50 | Including `grpc++` and reflection |
| Protobuf | 3.21 | `protoc` and `protoc-gen-grpc` |
| Vulkan SDK | 1.3 _(optional)_ | For GPU acceleration |
| Python | 3.9+ | For the Python clients only |

> **llama.cpp submodule:** this project pins llama.cpp at **b8925** (April 2026), which uses the `llama_memory_t` API introduced to replace the older `llama_kv_cache_clear`. Older llama.cpp checkouts are not compatible.

### Install dependencies

**Ubuntu / Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake git pkg-config \
    libgrpc++-dev libprotobuf-dev \
    protobuf-compiler protobuf-compiler-grpc \
    libvulkan-dev glslc   # optional, for GPU
```

**Arch Linux / CachyOS:**
```bash
sudo pacman -Sy
sudo pacman -S --needed base-devel cmake git grpc protobuf
sudo pacman -S --needed vulkan-headers shaderc   # optional, for GPU
```

**Fedora / RHEL / CentOS / Rocky / AlmaLinux:**
```bash
sudo dnf makecache
sudo dnf install -y gcc-c++ cmake git pkgconfig \
    grpc-devel grpc-plugins protobuf-devel protobuf-compiler
sudo dnf install -y vulkan-headers glslc   # optional, for GPU
```

**Slackware:**

`gRPC` and `Protobuf` are not in the official Slackware package tree. Install base tools with `slackpkg`, then build the rest from [SlackBuilds.org](https://slackbuilds.org) via `sbopkg`:
```bash
sudo slackpkg update
sudo slackpkg install cmake git
sudo sbopkg -i protobuf
sudo sbopkg -i grpc
sudo sbopkg -i vulkan-sdk   # optional, for GPU
sudo sbopkg -i shaderc      # optional, for GPU
```

**macOS (Homebrew):**
```bash
brew install cmake grpc protobuf
```

## Installation

### Quick install (Linux only)

```bash
git clone --recursive https://github.com/soumenkdeb/llama-grpc-server.git
cd llama-grpc-server
bash install.sh
```

The installer detects your package manager (apt, pacman, dnf/yum, or slackpkg), installs missing dependencies, initialises the `llama.cpp` submodule, and builds the binary into `build/`.

Elevated privileges (`sudo`) are used only when necessary — package installation always needs root, but binary installation is silent if the target directory is already writable by the current user.

```bash
bash install.sh --help          # full option reference
bash install.sh --no-vulkan     # CPU-only build (no Vulkan dependency)
bash install.sh --prefix ~/.local        # user-local install, no sudo needed

# Build and install system-wide to /usr/local/bin:
INSTALL_SYSTEM=1 bash install.sh
INSTALL_SYSTEM=1 bash install.sh --prefix /usr/local --no-vulkan
```

> **macOS users:** `install.sh` is Linux-only. Follow the manual build steps below after installing prerequisites with `brew install cmake grpc protobuf`.

### Manual build

```bash
git clone --recursive https://github.com/soumenkdeb/llama-grpc-server.git
cd llama-grpc-server

# Initialise the llama.cpp submodule if you did not clone with --recursive:
git submodule update --init --recursive

# Configure (add -DGGML_VULKAN=OFF for CPU-only):
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release

# Build:
cmake --build build --parallel $(nproc)
```

The compiled binary is at `build/llama-grpc-server`.

```
build/llama-grpc-server --help
```
```
Usage: build/llama-grpc-server <model_path> [port]
  model_path  Path to GGUF model file (default: models/llama-3.2-3B.gguf)
  port        Port to listen on (default: 50051)
```

## Download a Model

Download any GGUF model from Hugging Face and place it in the `models/` directory.

```bash
mkdir -p models
```

### Method 1 — wget (simplest)

Paste the direct URL from the Hugging Face file page (click the download arrow → copy link):

```bash
# Llama 3.2 3B Instruct Q5 (~2.4 GB)
wget https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q5_K_M.gguf \
    -O models/llama3.2-3b.gguf

# Phi-3.5 Mini Q4 (~2.2 GB)
wget https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf \
    -O models/phi-3.5-mini.gguf

# Qwen 2.5 7B Instruct Q4 (~4.7 GB)
wget https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf \
    -O models/qwen2.5-7b.gguf
```

Add `-c` to resume an interrupted download: `wget -c <url> -O models/...`

### Method 2 — curl

```bash
curl -L https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q5_K_M.gguf \
    -o models/llama3.2-3b.gguf
```

### Method 3 — huggingface-cli

Lets you browse and download by repo + filename without constructing URLs manually:

```bash
pip install huggingface-hub

# Llama 3.2 3B Instruct Q4
huggingface-cli download bartowski/Llama-3.2-3B-Instruct-GGUF \
    Llama-3.2-3B-Instruct-Q4_K_M.gguf --local-dir models

# Phi-3.5 Mini Q4
huggingface-cli download bartowski/Phi-3.5-mini-instruct-GGUF \
    Phi-3.5-mini-instruct-Q4_K_M.gguf --local-dir models
```

For gated models (e.g. Llama 3 from Meta) log in first: `huggingface-cli login`

### Choosing a quantisation level

The `Q` suffix in the filename controls the size/quality trade-off:

| Quant | RAM (3B model) | Quality | When to use |
|-------|---------------|---------|-------------|
| `Q8_0` | ~3.5 GB | Best | Plenty of VRAM / RAM |
| `Q5_K_M` | ~2.4 GB | Very good | Recommended balance |
| `Q4_K_M` | ~2.0 GB | Good | Tight on memory |
| `Q3_K_M` | ~1.6 GB | Fair | Very limited RAM |

`K_M` variants use a mixed-precision scheme that preserves quality better than plain `Q4_0` / `Q5_0` at the same size — prefer `K_M` when available.

### Where to find models

- **[bartowski](https://huggingface.co/bartowski)** — high-quality GGUF conversions of popular models
- **[TheBloke](https://huggingface.co/TheBloke)** — large archive of older conversions
- **[Hugging Face search](https://huggingface.co/models?library=gguf)** — filter by `gguf` library tag

## Running the Server

### Using the helper script (recommended)

```bash
# Auto-discover first .gguf in models/
bash scripts/start_server.sh

# Specify model and port
bash scripts/start_server.sh models/llama3.2-3b.gguf 50051
```

### Directly

```bash
# Show usage:
./build/llama-grpc-server --help

# Start with defaults (models/llama-3.2-3B.gguf, port 50051):
./build/llama-grpc-server models/llama3.2-3b.gguf

# Custom port:
./build/llama-grpc-server models/phi-3.5-mini.gguf 50052
```

On startup you should see:
```
Starting gRPC server with model: models/llama3.2-3b.gguf
gRPC server listening on 0.0.0.0:50051
```

The server loads the model into memory once and serves all subsequent requests without reloading. The KV memory cache (`llama_memory_t`) is cleared between requests to prevent context overflow.

## Python Clients

### Setup

```bash
cd llama-grpc-py-client
python -m venv .
source bin/activate          # Linux / macOS
# bin\activate.bat           # Windows

pip install -r requirements.txt
```

### Interactive chat (multi-turn)

```bash
python interactive.py                           # localhost:50051
python interactive.py --host 192.168.1.10       # remote server
python interactive.py --port 50052              # custom port
```

```
llama-gRPC Interactive Chat
Connected to localhost:50051
Type 'exit' or 'quit' to end the conversation.

You: What is the capital of France?
Assistant: The capital of France is Paris.

You: What is it famous for?
Assistant: Paris is famous for the Eiffel Tower, the Louvre Museum...

You: exit
Goodbye!
```

### One-shot client

```bash
python client.py "Explain gRPC in one paragraph."

# Or pass input interactively:
python client.py
You: Hello, how are you?
```

### Connecting to a non-default host or port

Use the `--host` and `--port` flags:
```bash
python interactive.py --host myserver --port 50052
python client.py --host myserver --port 50052 "Hello"
```

## gRPC API

The service is defined in [`protos/llama.proto`](protos/llama.proto).

### `ChatCompletion` (server-streaming RPC)

**Request: `ChatCompletionRequest`**

| Field | Type | Description |
|-------|------|-------------|
| `messages` | `repeated Message` | Conversation history (system, user, assistant) |
| `max_tokens` | `uint32` | Maximum tokens to generate (default: 512) |
| `temperature` | `float` | Sampling temperature 0.0–2.0 (default: 0.7) |
| `top_k` | `uint32` | Top-K sampling (default: 40) |
| `top_p` | `float` | Nucleus sampling probability (default: 0.95) |

**`Message`**

| Field | Type | Description |
|-------|------|-------------|
| `role` | `string` | `"system"`, `"user"`, or `"assistant"` |
| `content` | `string` | Message text |

**Response stream: `ChatCompletionResponse`**

| Field | Type | Description |
|-------|------|-------------|
| `delta` | `string` | Next token text fragment |
| `finish_reason` | `string` | Empty during generation; `"stop"` on EOS |

### Example with grpcurl

```bash
grpcurl -plaintext -d '{
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user",   "content": "Hello!"}
  ],
  "max_tokens": 128,
  "temperature": 0.7
}' localhost:50051 llama.LlamaService/ChatCompletion
```

## Configuration

| Parameter | Default | How to change |
|-----------|---------|---------------|
| Model path | `models/llama-3.2-3B.gguf` | First CLI argument |
| Port | `50051` | Second CLI argument or `LLAMA_PORT` env var |
| Context length | 8192 | Recompile: `ctx_params.n_ctx` in `llama_grpc_service.cpp` |
| Batch size | 512 | Recompile: `ctx_params.n_batch` |

## Limitations

- **Single concurrent request**: The context is shared across requests and is not thread-safe. Concurrent calls will produce incorrect results. This is suitable for personal/development use.
- **No TLS**: The server uses insecure credentials. Do not expose port 50051 to untrusted networks without a TLS proxy (e.g. nginx, Envoy).
- **Chat template**: A generic `<|role|>\ncontent\n` template is used. Models with custom chat templates (e.g. Llama 3's `<|begin_of_text|>` format) may produce suboptimal results. Contributions to add proper template support are welcome.
- **llama.cpp API**: Uses the `llama_memory_t` API (b8925+). The older `llama_kv_cache_clear` API is not supported.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for code standards and the pull request workflow.

## License

[MIT License](LICENSE) — Copyright (c) 2025 Soumen K Deb
