# Aho-Corasick CUDA GPU

A high-performance implementation of the Aho-Corasick string matching algorithm with GPU acceleration using CUDA, packaged as an npm module.

## Description

This project provides both CPU and GPU implementations of the Aho-Corasick algorithm, a string searching algorithm that can efficiently locate multiple pattern strings in a text simultaneously. The GPU implementation leverages CUDA for parallel processing, making it suitable for large-scale pattern matching tasks.

## Prerequisites

- Node.js (v14 or higher)
- CUDA Toolkit (11.0 or higher)
- C++ compiler compatible with your Node.js version
- npm (comes with Node.js)

## Installation

```bash
npm install aho-corasick-cuda-gpu
```

For development installation from the GitHub repository:

```bash
git clone https://github.com/yourusername/aho-corasick-cuda-gpu.git
cd aho-corasick-cuda-gpu
npm install
```

## Usage Example

Here's an example of how to use the package to search for patterns in a text string:

```javascript
const ahoCorasick = require('aho-corasick-cuda-gpu');

// Define patterns to search for
const patterns = ['the', 'and', 'that', 'have'];

// Example usage with a text string
const text = 'the quick brown fox and the lazy dog';
ahoCorasick.findMatches(text, patterns)
  .then(matches => {
    console.log('Matches:', matches);
    // Output: Matches: [
    //   { pattern: 'the', count: 2 },
    //   { pattern: 'and', count: 1 },
    //   { pattern: 'that', count: 0 },
    //   { pattern: 'have', count: 0 }
    // ]
  })
  .catch(error => {
    console.error('Error:', error);
  });
```

### Processing Large Files

For processing large files (e.g., 1GB or larger), check out the sample script `test_aho_corasick.js` in the repository. It demonstrates:
- Processing large files in chunks
- GPU-accelerated pattern matching
- Progress tracking
- Memory-efficient file handling

To run the sample:
```bash
node test_aho_corasick.js
```

## API Reference

### findMatches(text, patterns)

Searches for multiple patterns in a text using the GPU-accelerated Aho-Corasick algorithm.

**Parameters:**
- `text` (string): The text to search in
- `patterns` (string[]): Array of patterns to search for

**Returns:**
- Promise that resolves to an array of objects with the following properties:
  - `pattern` (string): The pattern that was searched for
  - `count` (number): The number of occurrences of the pattern in the text

### processFile(filePath, patterns, options)

Processes a large file directly using the GPU-accelerated Aho-Corasick algorithm. This is more efficient than reading the file in chunks and calling `findMatches` on each chunk.

**Parameters:**
- `filePath` (string): Path to the file to process
- `patterns` (string[]): Array of patterns to search for
- `options` (object): Optional configuration
  - `chunkSize` (number): Size of each chunk in bytes (default: 64MB)
  - `onProgress` (function): Callback for progress updates

**Returns:**
- Promise that resolves to an array of objects with the following properties:
  - `pattern` (string): The pattern that was searched for
  - `count` (number): The number of occurrences of the pattern in the file

**Example:**
```javascript
const ahoCorasick = require('aho-corasick-cuda-gpu');

const patterns = ['the', 'and', 'that', 'have'];
const filePath = 'path/to/large/file.txt';

ahoCorasick.processFile(filePath, patterns, {
  chunkSize: 64 * 1024 * 1024, // 64MB chunks
  onProgress: (progress) => {
    console.log(`Progress: ${progress.percentage.toFixed(2)}% complete`);
  }
})
.then(results => {
  console.log('Results:', results);
})
.catch(error => {
  console.error('Error:', error);
});
```

## Building from Source

To build the project from source:

```bash
npm run build
```

This will compile the C++/CUDA code and create the native Node.js addon.

## Project Structure

```
.
├── build/                  # Build output directory
├── lib/                    # JavaScript wrapper code
│   └── index.js            # Main module entry point
├── node_modules/           # Node.js dependencies
├── src/                    # Source code
│   ├── aho_corasick.cpp    # CPU implementation
│   ├── aho_corasick.h      # CPU header file
│   ├── aho_corasick_gpu.cu # GPU implementation
│   ├── aho_corasick_gpu.cuh # GPU header file
│   └── node_binding.cpp    # Node.js native binding
├── binding.gyp             # Native addon build configuration
├── main.cu                 # Example standalone CUDA application
├── package.json            # npm package configuration
├── test_aho_corasick.js    # Example for processing large files
└── README.md               # This file
```

## Performance

The GPU-accelerated implementation can process text at rates of several GB/s on modern GPUs, making it suitable for applications that need to search for multiple patterns in large text corpora.

## License

MIT