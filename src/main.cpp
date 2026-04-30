#include <grpcpp/grpcpp.h>
#include <iostream>
#include <csignal>
#include <atomic>
#include "llama.grpc.pb.h"
#include "llama_grpc_service.h"

static std::atomic<bool> shutdown_requested(false);
static std::unique_ptr<grpc::Server> g_server;

static void signal_handler(int signum) {
    std::cout << "\nShutdown signal received (" << signum << "), gracefully shutting down..." << std::endl;
    shutdown_requested = true;
    if (g_server) {
        g_server->Shutdown();
    }
}

static void print_usage(const char* prog) {
    std::cerr << "Usage: " << prog << " <model_path> [port]\n"
              << "  model_path  Path to GGUF model file (default: models/llama-3.2-3B.gguf)\n"
              << "  port        Port to listen on (default: 50051)\n";
}

int main(int argc, char** argv) {
    if (argc > 1 && (std::string(argv[1]) == "--help" || std::string(argv[1]) == "-h")) {
        print_usage(argv[0]);
        return 0;
    }

    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    std::string model_path = (argc > 1) ? argv[1] : "models/llama-3.2-3B.gguf";
    std::string port       = (argc > 2) ? argv[2] : "50051";
    std::string server_address = "0.0.0.0:" + port;

    std::cout << "Starting gRPC server with model: " << model_path << std::endl;

    LlamaGrpcService service(model_path);

    grpc::ServerBuilder builder;
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    builder.RegisterService(&service);

    g_server = builder.BuildAndStart();
    std::cout << "gRPC server listening on " << server_address << std::endl;
    g_server->Wait();
    g_server.reset();
    std::cout << "Server shutdown complete" << std::endl;
    return 0;
}
