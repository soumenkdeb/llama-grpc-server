#pragma once

#include "llama.grpc.pb.h"
#include "llama.pb.h"
#include <llama.h>
#include <memory>
#include <string>
#include <vector>
#include <mutex>

class LlamaGrpcService final : public llama::LlamaService::Service {
public:
    LlamaGrpcService(const std::string& model_path);
    ~LlamaGrpcService() override;

    grpc::Status ChatCompletion(
        grpc::ServerContext* context,
        const llama::ChatCompletionRequest* request,
        grpc::ServerWriter<llama::ChatCompletionResponse>* writer
    ) override;

private:
    llama_model*   model_ = nullptr;
    llama_context* ctx_ = nullptr;
    mutable std::mutex ctx_mutex_;

    std::string apply_chat_template(const llama::ChatCompletionRequest* request);
    
    bool generate_token_stream(
        const std::string& prompt,
        uint32_t max_tokens,
        float temperature,
        uint32_t top_k,
        float top_p,
        grpc::ServerWriter<llama::ChatCompletionResponse>* writer
    );
};
