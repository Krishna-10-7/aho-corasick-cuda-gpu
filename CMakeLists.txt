cmake_minimum_required(VERSION 3.10)
project(aho_corasick_gpu CUDA CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set CUDA architectures
set(CMAKE_CUDA_ARCHITECTURES 75)  # Adjust based on your GPU
set(CMAKE_CUDA_STANDARD 17)

# Enable CUDA as a language
enable_language(CUDA)

# Set CUDA specific flags
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --extended-lambda")

# Source files
set(SOURCES
    src/aho_corasick.cpp
    src/aho_corasick_gpu.cu
    main.cu
)

# Header files
set(HEADERS
    src/aho_corasick.h
    src/aho_corasick_gpu.cuh
)

# Create executable
add_executable(aho_corasick_gpu ${SOURCES} ${HEADERS})

# Set CUDA specific properties
set_target_properties(aho_corasick_gpu PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
)

# Include directories
target_include_directories(aho_corasick_gpu PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Link CUDA libraries
target_link_libraries(aho_corasick_gpu
    ${CUDA_LIBRARIES}
    ${CUDA_CUDART_LIBRARY}
)

# Install targets
install(TARGETS aho_corasick_gpu
    RUNTIME DESTINATION bin
)

install(FILES ${HEADERS} DESTINATION include)