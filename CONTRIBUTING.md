# Contributing to llama-grpc-server

Thank you for your interest in contributing! This document covers the development workflow, code standards, and how to submit changes.

## Getting Started

1. Fork the repository and clone your fork:
   ```bash
   git clone --recursive https://github.com/your-fork/llama-grpc-server.git
   ```
2. Create a feature branch:
   ```bash
   git checkout -b feature/my-change
   ```
3. Build and verify the server runs before making changes (see [README.md](README.md)).

## Development Environment

| Tool | Minimum version |
|------|----------------|
| CMake | 3.22 |
| C++ compiler | GCC 11 / Clang 14 (C++17 required) |
| gRPC | 1.50 |
| Protobuf | 3.21 |
| Python | 3.9 (for client) |

## Code Standards

### C++

- Standard: C++17. No language extensions.
- Naming: `snake_case` for variables and functions, `PascalCase` for classes, `UPPER_SNAKE_CASE` for constants.
- Members: private members use a trailing underscore (e.g. `model_`).
- Headers: use `#pragma once`.
- Error handling: throw `std::runtime_error` from constructors; return `grpc::Status` from RPC handlers — never `std::terminate`.
- Memory: prefer RAII. Free llama.cpp resources in destructors in reverse-acquisition order (`context` → `model`). Per-request samplers are stack-local in `generate_token_stream` and freed before the function returns.
- Do not commit generated files (`*.pb.cc`, `*.pb.h`, `*.grpc.pb.*`).

### Python

- Style: PEP 8. Format with `black` before committing.
- Type hints encouraged for public function signatures.
- Do not commit virtual environment files (`bin/`, `lib/`, `pyvenv.cfg`).
- Generated protobuf files (`llama_pb2.py`, `llama_pb2_grpc.py`) **may** be committed to the `llama-grpc-py-client/` directory to ease usage.

### Proto

- Follow [Protobuf style guide](https://protobuf.dev/programming-guides/style/).
- Field names: `snake_case`. Message names: `PascalCase`.
- Increment field numbers monotonically; never reuse a deleted field number.

## Submitting Changes

1. Run a full build and make sure the server starts cleanly with your chosen model.
2. Test the Python clients (`client.py` and `interactive.py`) against your running server.
3. Keep commits focused; one logical change per commit.
4. Open a pull request against `main` with a clear description of what changed and why.
5. Reference any relevant issue numbers in the PR description.

## Reporting Bugs

Open a GitHub issue with:
- OS and distribution
- CPU / GPU and driver versions
- GGUF model used
- Exact command that reproduces the problem
- Full error output

## Security

Please **do not** open public issues for security vulnerabilities. Email the maintainer directly or use GitHub private security advisories.

## License

By contributing you agree that your changes will be licensed under the [MIT License](LICENSE).
