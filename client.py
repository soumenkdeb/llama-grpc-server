#!/usr/bin/env python3
"""
One-shot chat client for llama-gRPC Server.

Usage:
    python client.py "Your question here"
    python client.py --host 192.168.1.10 --port 50052 "Question"
    python client.py                        # prompts interactively

The generated protobuf bindings (llama_pb2*.py) are loaded from
llama-grpc-py-client/, so run this from the repository root.
"""

import argparse
import grpc
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "llama-grpc-py-client"))

import llama_pb2
import llama_pb2_grpc


def chat(user_message: str, host: str = "localhost", port: int = 50051) -> None:
    channel = grpc.insecure_channel(f"{host}:{port}")
    stub = llama_pb2_grpc.LlamaServiceStub(channel)

    request = llama_pb2.ChatCompletionRequest(
        messages=[
            llama_pb2.Message(role="system", content="You are a helpful assistant."),
            llama_pb2.Message(role="user", content=user_message),
        ],
        max_tokens=512,
        temperature=0.7,
        top_k=40,
        top_p=0.95,
    )

    print("Assistant: ", end="", flush=True)

    try:
        for response in stub.ChatCompletion(request):
            print(response.delta, end="", flush=True)
            if response.finish_reason:
                print()
                break
    except grpc.RpcError as e:
        print(f"\nError: {e.details()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="One-shot llama-gRPC chat client")
    parser.add_argument("message", nargs="*", help="Message to send (prompted if omitted)")
    parser.add_argument("--host", default="localhost", help="Server host (default: localhost)")
    parser.add_argument("--port", type=int, default=50051, help="Server port (default: 50051)")
    args = parser.parse_args()

    if args.message:
        user_input = " ".join(args.message)
    else:
        user_input = input("You: ").strip()

    if user_input:
        chat(user_input, host=args.host, port=args.port)
