#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <chrono>
#include <sstream>
#include <algorithm>
#include <cstring>
#include "src/aho_corasick.h"
#include "src/aho_corasick_gpu.cuh"

// Function to generate a 1GB test file
void generateTestFile(const std::string& filename, size_t sizeGB = 1) {
    std::ofstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Failed to create file: " << filename << std::endl;
        return;
    }

    const std::vector<std::string> words = {
        "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
        "and", "that", "have", "for", "not", "with", "you", "this", "but"
    };

    const size_t targetSize = sizeGB * 1024 * 1024 * 1024;
    size_t currentSize = 0;
    size_t reportInterval = targetSize / 10; // Report progress every 10%
    size_t nextReport = reportInterval;

    std::cout << "Generating " << sizeGB << "GB test file..." << std::endl;

    while (currentSize < targetSize) {
        std::string word = words[rand() % words.size()] + " ";
        file.write(word.c_str(), word.length());
        currentSize += word.length();

        if (currentSize >= nextReport) {
            std::cout << "Progress: " << (currentSize * 100 / targetSize) << "%" << std::endl;
            nextReport += reportInterval;
        }
    }

    file.close();
    std::cout << "Test file generated: " << filename << std::endl;
}

// Function to read file in chunks
std::vector<std::string> readFileInChunks(const std::string& filename, size_t chunkSize = 64 * 1024 * 1024) {
    std::vector<std::string> chunks;
    std::ifstream file(filename, std::ios::binary);
    
    if (!file) {
        std::cerr << "Failed to open file: " << filename << std::endl;
        return chunks;
    }

    // Get file size
    file.seekg(0, std::ios::end);
    size_t fileSize = file.tellg();
    file.seekg(0, std::ios::beg);

    // Calculate number of chunks
    size_t numChunks = (fileSize + chunkSize - 1) / chunkSize;
    chunks.reserve(numChunks);

    std::vector<char> buffer(chunkSize);
    size_t totalRead = 0;

    while (totalRead < fileSize) {
        size_t remaining = fileSize - totalRead;
        size_t toRead = std::min(chunkSize, remaining);
        
        file.read(buffer.data(), toRead);
        chunks.emplace_back(buffer.data(), toRead);
        
        totalRead += toRead;
        std::cout << "Read progress: " << (totalRead * 100 / fileSize) << "%" << std::endl;
    }

    return chunks;
}

// Function to read patterns from a file
std::vector<std::string> readPatternsFromFile(const std::string& filename) {
    std::vector<std::string> patterns;
    std::ifstream file(filename);
    if (!file) {
        std::cerr << "Failed to open patterns file: " << filename << std::endl;
        return patterns;
    }

    std::string line;
    while (std::getline(file, line)) {
        if (!line.empty()) {
            patterns.push_back(line);
        }
    }

    return patterns;
}

// Function to read text from a file
std::string readTextFromFile(const std::string& filename) {
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Failed to open text file: " << filename << std::endl;
        return "";
    }

    // Get file size
    file.seekg(0, std::ios::end);
    size_t fileSize = file.tellg();
    file.seekg(0, std::ios::beg);

    // Read the entire file
    std::string text(fileSize, ' ');
    file.read(&text[0], fileSize);
    
    return text;
}

// Function to write results to a JSON file
void writeResultsToJson(const std::string& filename, 
                        const std::vector<std::string>& patterns, 
                        const std::vector<long long>& pattern_counts) {
    std::ofstream file(filename);
    if (!file) {
        std::cerr << "Failed to create output file: " << filename << std::endl;
        return;
    }

    file << "[" << std::endl;
    for (size_t i = 0; i < patterns.size(); ++i) {
        file << "  {" << std::endl;
        file << "    \"pattern\": \"" << patterns[i] << "\"," << std::endl;
        file << "    \"count\": " << pattern_counts[i] << std::endl;
        file << "  }";
        if (i < patterns.size() - 1) {
            file << ",";
        }
        file << std::endl;
    }
    file << "]" << std::endl;
}

// Function to print usage information
void printUsage(const char* programName) {
    std::cerr << "Usage: " << programName << " [OPTIONS]" << std::endl;
    std::cerr << "Options:" << std::endl;
    std::cerr << "  --text FILE       Text file to search in" << std::endl;
    std::cerr << "  --patterns FILE   File containing patterns (one per line)" << std::endl;
    std::cerr << "  --output FILE     Output file for results" << std::endl;
    std::cerr << "  --json            Output results in JSON format" << std::endl;
    std::cerr << "  --chunk-size SIZE Chunk size in MB (default: 64)" << std::endl;
    std::cerr << "  --help            Display this help message" << std::endl;
}

int main(int argc, char* argv[]) {
    // Default values
    std::string textFile;
    std::string patternsFile;
    std::string outputFile;
    bool jsonOutput = false;
    size_t chunkSizeMB = 64;
    
    // Parse command line arguments
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--text") == 0 && i + 1 < argc) {
            textFile = argv[++i];
        } else if (strcmp(argv[i], "--patterns") == 0 && i + 1 < argc) {
            patternsFile = argv[++i];
        } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
            outputFile = argv[++i];
        } else if (strcmp(argv[i], "--json") == 0) {
            jsonOutput = true;
        } else if (strcmp(argv[i], "--chunk-size") == 0 && i + 1 < argc) {
            chunkSizeMB = std::stoi(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0) {
            printUsage(argv[0]);
            return 0;
        } else {
            std::cerr << "Unknown option: " << argv[i] << std::endl;
            printUsage(argv[0]);
            return 1;
        }
    }
    
    // Check required arguments
    if (textFile.empty() || patternsFile.empty()) {
        std::cerr << "Error: Text file and patterns file are required" << std::endl;
        printUsage(argv[0]);
        return 1;
    }
    
    // Read patterns
    std::vector<std::string> patterns = readPatternsFromFile(patternsFile);
    if (patterns.empty()) {
        std::cerr << "Error: No patterns found in file" << std::endl;
        return 1;
    }
    
    // Build CPU automaton
    auto start = std::chrono::high_resolution_clock::now();
    if (!jsonOutput) std::cout << "Building Aho-Corasick automaton..." << std::endl;
    auto cpu_automaton = buildAutomatonCPU(patterns);
    
    // Transfer to GPU
    if (!jsonOutput) std::cout << "Transferring automaton to GPU..." << std::endl;
    auto gpu_automaton = transferAutomatonToGPU(cpu_automaton);
    
    auto setup_end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> setup_time = setup_end - start;
    if (!jsonOutput) std::cout << "Setup time: " << setup_time.count() << " seconds" << std::endl;
    
    // Process text
    if (!jsonOutput) std::cout << "Starting pattern search..." << std::endl;
    std::vector<long long> pattern_counts(patterns.size(), 0);
    
    // Read text in chunks if it's a large file
    std::ifstream fileCheck(textFile);
    fileCheck.seekg(0, std::ios::end);
    size_t fileSize = fileCheck.tellg();
    fileCheck.close();
    
    auto search_start = std::chrono::high_resolution_clock::now();
    
    if (fileSize > chunkSizeMB * 1024 * 1024) {
        // Process large file in chunks
        auto chunks = readFileInChunks(textFile, chunkSizeMB * 1024 * 1024);
        
        for (size_t i = 0; i < chunks.size(); ++i) {
            if (!jsonOutput) std::cout << "Processing chunk " << (i + 1) << "/" << chunks.size() << std::endl;
            auto matches = searchGPU(chunks[i], gpu_automaton);
            
            // Aggregate results
            for (const auto& match : matches) {
                if (match.pattern_index >= 0 && match.pattern_index < patterns.size()) {
                    pattern_counts[match.pattern_index]++;
                }
            }
        }
    } else {
        // Process small file in one go
        std::string text = readTextFromFile(textFile);
        auto matches = searchGPU(text, gpu_automaton);
        
        // Aggregate results
        for (const auto& match : matches) {
            if (match.pattern_index >= 0 && match.pattern_index < patterns.size()) {
                pattern_counts[match.pattern_index]++;
            }
        }
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> search_time = end - search_start;
    std::chrono::duration<double> total_time = end - start;
    
    // Output results
    if (jsonOutput) {
        if (!outputFile.empty()) {
            writeResultsToJson(outputFile, patterns, pattern_counts);
        } else {
            // Print JSON to stdout
            std::cout << "[" << std::endl;
            for (size_t i = 0; i < patterns.size(); ++i) {
                std::cout << "  {" << std::endl;
                std::cout << "    \"pattern\": \"" << patterns[i] << "\"," << std::endl;
                std::cout << "    \"count\": " << pattern_counts[i] << std::endl;
                std::cout << "  }";
                if (i < patterns.size() - 1) {
                    std::cout << ",";
                }
                std::cout << std::endl;
            }
            std::cout << "]" << std::endl;
        }
    } else {
        // Print human-readable results
        std::cout << "\nSearch Results:" << std::endl;
        std::cout << "---------------" << std::endl;
        for (size_t i = 0; i < patterns.size(); ++i) {
            std::cout << "Pattern \"" << patterns[i] << "\": " << pattern_counts[i] << " matches" << std::endl;
        }
        
        std::cout << "\nPerformance Metrics:" << std::endl;
        std::cout << "-------------------" << std::endl;
        std::cout << "Setup time: " << setup_time.count() << " seconds" << std::endl;
        std::cout << "Search time: " << search_time.count() << " seconds" << std::endl;
        std::cout << "Total time: " << total_time.count() << " seconds" << std::endl;
        std::cout << "Processing speed: " << (fileSize / (1024.0 * 1024.0 * 1024.0) / search_time.count()) << " GB/s" << std::endl;
    }
    
    return 0;
}