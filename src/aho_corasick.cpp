#include "aho_corasick.h"
#include <iostream>

std::vector<ACNodeCPU> buildAutomatonCPU(const std::vector<std::string>& patterns) {
    std::vector<ACNodeCPU> nodes;
    nodes.emplace_back();

    int pattern_idx = 0;
    for (const std::string& pattern : patterns) {
        int current_node_idx = 0;
        for (char ch : pattern) {
            auto it = nodes[current_node_idx].transitions.find(ch);
            if (it == nodes[current_node_idx].transitions.end()) {
                int next_node_idx = nodes.size();
                nodes.emplace_back();
                nodes[next_node_idx].parent = current_node_idx;
                nodes[next_node_idx].parent_char = ch;
                nodes[current_node_idx].transitions[ch] = next_node_idx;
                current_node_idx = next_node_idx;
            } else {
                current_node_idx = it->second;
            }
        }
        nodes[current_node_idx].output_patterns.push_back(pattern_idx);
        pattern_idx++;
    }

    std::queue<int> q;

    for (auto const& [key, val] : nodes[0].transitions) {
        nodes[val].failure_link = 0;
        q.push(val);
    }
    nodes[0].failure_link = 0;

    while (!q.empty()) {
        int current_node_idx = q.front();
        q.pop();

        for (auto const& [ch, next_node_idx] : nodes[current_node_idx].transitions) {
            q.push(next_node_idx);
            int failure_target_idx = nodes[current_node_idx].failure_link;

            while (nodes[failure_target_idx].transitions.find(ch) == nodes[failure_target_idx].transitions.end() && failure_target_idx != 0) {
                failure_target_idx = nodes[failure_target_idx].failure_link;
            }

            auto it = nodes[failure_target_idx].transitions.find(ch);
            if (it != nodes[failure_target_idx].transitions.end()) {
                nodes[next_node_idx].failure_link = it->second;
            } else {
                nodes[next_node_idx].failure_link = 0;
            }

            const auto& failure_outputs = nodes[nodes[next_node_idx].failure_link].output_patterns;
            nodes[next_node_idx].output_patterns.insert(
                nodes[next_node_idx].output_patterns.end(),
                failure_outputs.begin(),
                failure_outputs.end()
            );
        }
    }

    return nodes;
}
