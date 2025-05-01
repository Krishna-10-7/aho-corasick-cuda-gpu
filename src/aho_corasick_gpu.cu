#include "aho_corasick_gpu.cuh"
#include <cuda_runtime.h>
#include <vector>
#include <iostream>
#include <algorithm>

constexpr long long MAX_TEXT_LENGTH = 1LL << 32;
constexpr long long MAX_RESULTS = 1LL << 30;
constexpr long long MAX_PATTERNS = 1LL << 24;
constexpr long long MAX_NODES = 1LL << 26;

#define CUDA_CHECK(err) __cudaSafeCall(err, __FILE__, __LINE__)
inline void __cudaSafeCall(cudaError_t err, const char *file, const int line) {
    if (cudaSuccess != err) {
        fprintf(stderr, "CUDA error in file '%s' in line %d: %s.\n",
                file, line, cudaGetErrorString(err));
        exit(EXIT_FAILURE);
    }
}

AutomatonGPU::~AutomatonGPU() {
    if (d_nodes) CUDA_CHECK(cudaFree(d_nodes));
    if (d_output_patterns) CUDA_CHECK(cudaFree(d_output_patterns));
    d_nodes = nullptr;
    d_output_patterns = nullptr;
}

AutomatonGPU transferAutomatonToGPU(const std::vector<ACNodeCPU>& cpu_nodes) {
    AutomatonGPU gpu_automaton;
    gpu_automaton.node_count = cpu_nodes.size();

    int total_outputs = 0;
    for (const auto& node : cpu_nodes)
        total_outputs += node.output_patterns.size();
    gpu_automaton.total_output_count = total_outputs;

    CUDA_CHECK(cudaMalloc(&gpu_automaton.d_nodes, sizeof(ACNodeGPU) * gpu_automaton.node_count));
    CUDA_CHECK(cudaMalloc(&gpu_automaton.d_output_patterns, sizeof(int) * total_outputs));

    std::vector<ACNodeGPU> host_nodes(gpu_automaton.node_count);
    std::vector<int> host_outputs(total_outputs);
    int output_idx = 0;

    for (int i = 0; i < cpu_nodes.size(); i++) {
        const auto& cpu_node = cpu_nodes[i];
        auto& gpu_node = host_nodes[i];
        for (int c = 0; c < ALPHABET_SIZE; c++)
            gpu_node.transitions[c] = -1;
        for (const auto& [c, next] : cpu_node.transitions)
            gpu_node.transitions[c] = next;

        gpu_node.failure_link = cpu_node.failure_link;
        gpu_node.output_start_idx = output_idx;
        gpu_node.output_count = cpu_node.output_patterns.size();

        for (int pattern_idx : cpu_node.output_patterns)
            host_outputs[output_idx++] = pattern_idx;
    }

    CUDA_CHECK(cudaMemcpy(gpu_automaton.d_nodes, host_nodes.data(), 
        sizeof(ACNodeGPU) * gpu_automaton.node_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(gpu_automaton.d_output_patterns, host_outputs.data(),
        sizeof(int) * total_outputs, cudaMemcpyHostToDevice));

    return gpu_automaton;
}

__device__ int gpu_get_next_state(int current_state_idx, unsigned char ch, const ACNodeGPU* d_nodes) {
    int next_state_idx = d_nodes[current_state_idx].transitions[ch];
    if (next_state_idx != -1) return next_state_idx;

    if (current_state_idx != 0) {
        int failure_idx = d_nodes[current_state_idx].failure_link;
        while (d_nodes[failure_idx].transitions[ch] == -1 && failure_idx != 0)
            failure_idx = d_nodes[failure_idx].failure_link;
        next_state_idx = d_nodes[failure_idx].transitions[ch];
        if (next_state_idx != -1) return next_state_idx;
    }

    int root_transition = d_nodes[0].transitions[ch];
    return (root_transition != -1) ? root_transition : 0;
}

__global__ void ahoCorasickSearchKernelOptimized(const unsigned char* d_text,
                                                 long long text_length,
                                                 const ACNodeGPU* d_nodes,
                                                 const int* d_output_patterns,
                                                 MatchResult* d_results,
                                                 int* d_match_count,
                                                 long long max_results_capacity) {
    long long idx = blockIdx.x * blockDim.x + threadIdx.x;
    long long stride = gridDim.x * blockDim.x;
    int current_state_idx = 0;

    for (long long i = idx; i < text_length; i += stride) {
        current_state_idx = gpu_get_next_state(current_state_idx, d_text[i], d_nodes);
        int temp_state_idx = current_state_idx;

        while (temp_state_idx != 0) {
            const ACNodeGPU& node = d_nodes[temp_state_idx];
            for (int k = 0; k < node.output_count; ++k) {
                int match_idx = atomicAdd(d_match_count, 1);
                if (match_idx < max_results_capacity) {
                    d_results[match_idx].pattern_index = d_output_patterns[node.output_start_idx + k];
                    d_results[match_idx].text_position = i;
                }
            }
            int next = d_nodes[temp_state_idx].failure_link;
            if (next == d_nodes[next].failure_link && next != 0) break;
            temp_state_idx = next;
        }

        if (current_state_idx == 0) {
            const ACNodeGPU& root_node = d_nodes[0];
            for (int k = 0; k < root_node.output_count; ++k) {
                int match_idx = atomicAdd(d_match_count, 1);
                if (match_idx < max_results_capacity) {
                    d_results[match_idx].pattern_index = d_output_patterns[root_node.output_start_idx + k];
                    d_results[match_idx].text_position = i;
                }
            }
        }
    }
}

bool checkMemoryRequirements(long long text_length, long long pattern_count, long long node_count) {
    return !(text_length > MAX_TEXT_LENGTH || pattern_count > MAX_PATTERNS || node_count > MAX_NODES);
}

std::vector<MatchResult> searchGPU(const std::string& text, const AutomatonGPU& d_automaton) {
    long long text_length = text.length();
    if (text_length == 0 || d_automaton.node_count == 0) return {};

    if (!checkMemoryRequirements(text_length, d_automaton.total_output_count, d_automaton.node_count))
        throw std::runtime_error("Memory requirements exceed limits");

    unsigned char* d_text = nullptr;
    MatchResult* d_results = nullptr;
    int* d_match_count = nullptr;

    long long results_capacity = std::min(
        MAX_RESULTS,
        std::max(text_length * 2LL, (long long)d_automaton.total_output_count * 100)
    );

    size_t free_mem, total_mem;
    CUDA_CHECK(cudaMemGetInfo(&free_mem, &total_mem));
    size_t required_mem = text_length + results_capacity * sizeof(MatchResult) + sizeof(int);
    if (required_mem > free_mem)
        throw std::runtime_error("Insufficient GPU memory");

    CUDA_CHECK(cudaMalloc(&d_text, text_length));
    CUDA_CHECK(cudaMalloc(&d_results, results_capacity * sizeof(MatchResult)));
    CUDA_CHECK(cudaMalloc(&d_match_count, sizeof(int)));

    CUDA_CHECK(cudaMemcpy(d_text, text.c_str(), text_length, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemset(d_match_count, 0, sizeof(int)));

    int threads_per_block = 256;
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
    int blocks_per_grid = std::min(
        prop.multiProcessorCount * 16,
        (int)((text_length + threads_per_block - 1) / threads_per_block)
    );
    blocks_per_grid = std::max(1, blocks_per_grid);

    ahoCorasickSearchKernelOptimized<<<blocks_per_grid, threads_per_block>>>(
        d_text, text_length, d_automaton.d_nodes, d_automaton.d_output_patterns,
        d_results, d_match_count, results_capacity
    );
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    int h_match_count = 0;
    CUDA_CHECK(cudaMemcpy(&h_match_count, d_match_count, sizeof(int), cudaMemcpyDeviceToHost));

    std::vector<MatchResult> h_results;
    int results_to_copy = std::min((long long)h_match_count, results_capacity);
    if (results_to_copy > 0) {
        h_results.resize(results_to_copy);
        CUDA_CHECK(cudaMemcpy(h_results.data(), d_results, results_to_copy * sizeof(MatchResult), cudaMemcpyDeviceToHost));
    }

    CUDA_CHECK(cudaFree(d_text));
    CUDA_CHECK(cudaFree(d_results));
    CUDA_CHECK(cudaFree(d_match_count));

    return h_results;
}
