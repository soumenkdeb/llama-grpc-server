#include <grpcpp/grpcpp.h>
#include <iostream>
#include "llama.grpc.pb.h"
#include "llama_grpc_service.h"

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

    std::string model_path = (argc > 1) ? argv[1] : "models/llama-3.2-3B.gguf";
    std::string port       = (argc > 2) ? argv[2] : "50051";
    std::string server_address = "0.0.0.0:" + port;

    std::cout << "Starting gRPC server with model: " << model_path << std::endl;

    LlamaGrpcService service(model_path);

    grpc::ServerBuilder builder;
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    builder.RegisterService(&service);

    std::unique_ptr<grpc::Server> server(builder.BuildAndStart());
    std::cout << "gRPC server listening on " << server_address << std::endl;
    server->Wait();
    return 0;
}
