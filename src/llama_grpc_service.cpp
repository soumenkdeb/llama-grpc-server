#include "llama_grpc_service.h"
#include <iostream>
#include <sstream>

LlamaGrpcService::LlamaGrpcService(const std::string& model_path) {
    // Load model
    llama_model_params model_params = llama_model_default_params();
    model_ = llama_model_load_from_file(model_path.c_str(), model_params);

    if (!model_) {
        throw std::runtime_error("Failed to load model: " + model_path);
    }

    // Context parameters
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 8192;
    ctx_params.n_batch = 512;
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;

    ctx_ = llama_init_from_model(model_, ctx_params);
    if (!ctx_) {
        throw std::runtime_error("Failed to create context");
    }
}

LlamaGrpcService::~LlamaGrpcService() {
    if (ctx_)   llama_free(ctx_);
    if (model_) llama_model_free(model_);
}

std::string LlamaGrpcService::apply_chat_template(const llama::ChatCompletionRequest* request) {
    std::ostringstream oss;
    for (const auto& msg : request->messages()) {
        if (msg.role() == "system") {
            oss << "<|system|>\n" << msg.content() << "\n";
        } else if (msg.role() == "user") {
            oss << "<|user|>\n" << msg.content() << "\n";
        } else if (msg.role() == "assistant") {
            oss << "<|assistant|>\n" << msg.content() << "\n";
        }
    }
    oss << "<|assistant|>\n";
    return oss.str();
}

grpc::Status LlamaGrpcService::ChatCompletion(
    grpc::ServerContext* context,
    const llama::ChatCompletionRequest* request,
    grpc::ServerWriter<llama::ChatCompletionResponse>* writer)
{
    try {
        std::string prompt = apply_chat_template(request);

        std::lock_guard<std::mutex> lock(ctx_mutex_);
        bool success = generate_token_stream(
            prompt,
            request->max_tokens() > 0 ? request->max_tokens() : 512,
            request->temperature() > 0 ? request->temperature() : 0.7f,
            request->top_k() > 0 ? request->top_k() : 40,
            request->top_p() > 0 ? request->top_p() : 0.95f,
            writer
        );

        if (!success) {
            return grpc::Status(grpc::StatusCode::INTERNAL, "Generation failed");
        }
        return grpc::Status::OK;
    }
    catch (const std::exception& e) {
        return grpc::Status(grpc::StatusCode::INTERNAL, e.what());
    }
}

bool LlamaGrpcService::generate_token_stream(
    const std::string& prompt,
    uint32_t max_tokens,
    float temperature,
    uint32_t top_k,
    float top_p,
    grpc::ServerWriter<llama::ChatCompletionResponse>* writer)
{
    const llama_vocab* vocab = llama_model_get_vocab(model_);

    // Clear KV cache between requests to avoid context overflow
    llama_memory_clear(llama_get_memory(ctx_), true);

    // Tokenize — pre-allocate up to the full context size
    std::vector<llama_token> tokens(llama_n_ctx(ctx_));
    int32_t n_tokens = llama_tokenize(vocab, prompt.c_str(), prompt.size(),
                                      tokens.data(), tokens.size(), true, true);
    if (n_tokens < 0) {
        std::cerr << "Tokenization failed: buffer too small\n";
        return false;
    }
    tokens.resize(n_tokens);

    // llama_decode asserts n_tokens <= n_batch; split prompt into n_batch chunks
    const uint32_t n_batch = llama_n_batch(ctx_);
    for (int32_t i = 0; i < n_tokens; i += n_batch) {
        int32_t n = std::min((int32_t)n_batch, n_tokens - i);
        if (llama_decode(ctx_, llama_batch_get_one(tokens.data() + i, n)) != 0) {
            return false;
        }
    }

    // Build per-request sampler chain using caller-supplied parameters
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    llama_sampler* sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(static_cast<int32_t>(top_k)));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    llama_token new_token;
    llama::ChatCompletionResponse response;
    bool ok = true;

    for (uint32_t i = 0; i < max_tokens; ++i) {
        new_token = llama_sampler_sample(sampler, ctx_, -1);

        if (new_token == llama_vocab_eos(vocab)) {
            response.set_finish_reason("stop");
            writer->Write(response);
            break;
        }

        // 256 bytes > model's 48-byte max token length; avoids overflow of old 16-byte buf
        char piece_buf[256];
        int32_t len = llama_token_to_piece(vocab, new_token, piece_buf, sizeof(piece_buf), 0, true);
        std::string token_str = (len > 0) ? std::string(piece_buf, len) : "";

        response.set_delta(token_str);
        response.set_finish_reason("");

        if (!writer->Write(response)) {
            ok = false;
            break;
        }

        if (llama_decode(ctx_, llama_batch_get_one(&new_token, 1)) != 0) {
            ok = false;
            break;
        }
    }

    llama_sampler_free(sampler);
    return ok;
}
