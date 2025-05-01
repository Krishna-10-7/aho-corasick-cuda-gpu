#ifndef AHO_CORASICK_H
#define AHO_CORASICK_H

#include <vector>
#include <string>
#include <queue>
#include <map>

struct ACNodeCPU {
    std::map<char, int> transitions;
    int failure_link;
    std::vector<int> output_patterns;
    int parent;
    char parent_char;

    ACNodeCPU() : failure_link(-1), parent(-1), parent_char(0) {}
};

std::vector<ACNodeCPU> buildAutomatonCPU(const std::vector<std::string>& patterns);

#endif // AHO_CORASICK_H
