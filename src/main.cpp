#include <grpcpp/grpcpp.h>
#include <iostream>
#include <csignal>
#include <atomic>
#include <thread>
#include <condition_variable>
#include "llama.grpc.pb.h"
#include "llama_grpc_service.h"

static std::atomic<bool> shutdown_requested(false);
static std::unique_ptr<grpc::Server> g_server;
static std::condition_variable shutdown_cv;
static std::mutex shutdown_mutex;

static void signal_handler(int signum) {
    // Only set flag in signal handler, don't call gRPC functions
    shutdown_requested = true;
    shutdown_cv.notify_one();
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

    try {
        LlamaGrpcService service(model_path);
        std::cout << "Model loaded successfully" << std::endl;

        grpc::ServerBuilder builder;
        builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
        builder.RegisterService(&service);

        g_server = builder.BuildAndStart();
        if (!g_server) {
            std::cerr << "Failed to start gRPC server" << std::endl;
            return 1;
        }
        std::cout << "gRPC server listening on " << server_address << std::endl;

        // Shutdown thread: wait for signal, then safely call Shutdown()
        std::thread shutdown_thread([&]() {
            std::unique_lock<std::mutex> lock(shutdown_mutex);
            shutdown_cv.wait(lock, [] { return shutdown_requested.load(); });
            std::cout << "\nShutdown signal received, gracefully shutting down..." << std::endl;
            if (g_server) {
                g_server->Shutdown();
            }
        });

        g_server->Wait();
        shutdown_thread.join();
        g_server.reset();
        std::cout << "Server shutdown complete" << std::endl;
    }
    catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }
    catch (...) {
        std::cerr << "Unknown fatal error" << std::endl;
        return 1;
    }
    return 0;
}
