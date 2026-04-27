#!/usr/bin/env python3
"""
Interactive multi-turn chat client for llama-gRPC Server.

Usage:
    python interactive.py [--host HOST] [--port PORT]

Defaults: host=localhost, port=50051
Type 'exit', 'quit', or 'bye' to end the session.
"""

import argparse
import grpc
import sys
import llama_pb2
import llama_pb2_grpc


def main() -> None:
    parser = argparse.ArgumentParser(description="Interactive llama-gRPC chat client")
    parser.add_argument("--host", default="localhost", help="Server host (default: localhost)")
    parser.add_argument("--port", type=int, default=50051, help="Server port (default: 50051)")
    args = parser.parse_args()

    print("llama-gRPC Interactive Chat")
    print(f"Connected to {args.host}:{args.port}")
    print("Type 'exit' or 'quit' to end the conversation.\n")

    channel = grpc.insecure_channel(f"{args.host}:{args.port}")
    stub = llama_pb2_grpc.LlamaServiceStub(channel)

    messages = [
        llama_pb2.Message(role="system", content="You are a helpful assistant.")
    ]

    while True:
        try:
            user_input = input("You: ").strip()

            if user_input.lower() in ("exit", "quit", "bye"):
                print("Goodbye!")
                break

            if not user_input:
                continue

            messages.append(llama_pb2.Message(role="user", content=user_input))

            request = llama_pb2.ChatCompletionRequest(
                messages=messages,
                max_tokens=1024,
                temperature=0.7,
                top_k=40,
                top_p=0.95,
            )

            print("Assistant: ", end="", flush=True)
            response_text = ""

            for response in stub.ChatCompletion(request):
                print(response.delta, end="", flush=True)
                response_text += response.delta
                if response.finish_reason:
                    print()
                    break

            messages.append(llama_pb2.Message(role="assistant", content=response_text))

        except grpc.RpcError as e:
            print(f"\nConnection error: {e.details()}")
            print(f"Make sure the server is running on {args.host}:{args.port}.")
            break
        except KeyboardInterrupt:
            print("\nGoodbye!")
            break
        except Exception as e:
            print(f"\nUnexpected error: {e}")
            break


if __name__ == "__main__":
    main()
