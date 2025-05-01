#ifndef AHO_CORASICK_GPU_CUH
#define AHO_CORASICK_GPU_CUH

#include "aho_corasick.h"
#include <vector>
#include <string>

constexpr int ALPHABET_SIZE = 256;

struct ACNodeGPU {
    int transitions[ALPHABET_SIZE];
    int failure_link;
    int output_start_idx;
    int output_count;
};

struct AutomatonGPU {
    ACNodeGPU* d_nodes = nullptr;
    int* d_output_patterns = nullptr;
    int node_count = 0;
    int total_output_count = 0;

    ~AutomatonGPU();
};

struct MatchResult {
    int pattern_index;
    long long text_position;
};

AutomatonGPU transferAutomatonToGPU(const std::vector<ACNodeCPU>& cpu_nodes);
std::vector<MatchResult> searchGPU(const std::string& text, const AutomatonGPU& d_automaton);

#endif // AHO_CORASICK_GPU_CUH
