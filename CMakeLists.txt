cmake_minimum_required(VERSION 3.22)
project(llama-grpc-server LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf REQUIRED)

get_target_property(GRPC_CPP_PLUGIN gRPC::grpc_cpp_plugin LOCATION)

set(PROTO_FILES "${CMAKE_CURRENT_SOURCE_DIR}/protos/llama.proto")

protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS ${PROTO_FILES})
protobuf_generate(
    LANGUAGE grpc
    GENERATE_EXTENSIONS .grpc.pb.h .grpc.pb.cc
    PLUGIN "protoc-gen-grpc=${GRPC_CPP_PLUGIN}"
    PROTOS ${PROTO_FILES}
    OUT_VAR GRPC_SRCS
)

# Fix protobuf includes
add_custom_target(fix_proto_includes ALL
    COMMAND sed -i 's|"protos/llama.pb.h"|"llama.pb.h"|g' 
            ${CMAKE_CURRENT_BINARY_DIR}/protos/llama.grpc.pb.h
            ${CMAKE_CURRENT_BINARY_DIR}/protos/llama.grpc.pb.cc
    DEPENDS ${PROTO_SRCS} ${GRPC_SRCS}
)

add_subdirectory(llama.cpp)

add_executable(llama-grpc-server
    src/main.cpp
    src/llama_grpc_service.cpp
    ${PROTO_SRCS}
    ${GRPC_SRCS}
)

add_dependencies(llama-grpc-server fix_proto_includes)

target_link_libraries(llama-grpc-server PRIVATE
    llama
    ggml
    ggml-cpu
    gRPC::grpc++
    gRPC::grpc++_reflection
    protobuf::libprotobuf
)

# Link Vulkan backend only when it was compiled in
if(GGML_VULKAN)
    target_link_libraries(llama-grpc-server PRIVATE ggml-vulkan)
endif()

target_include_directories(llama-grpc-server PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}/protos
    ${CMAKE_CURRENT_SOURCE_DIR}
    llama.cpp/include
    llama.cpp/common
)

set_target_properties(llama-grpc-server PROPERTIES
    INSTALL_RPATH "$ORIGIN/bin"
)
