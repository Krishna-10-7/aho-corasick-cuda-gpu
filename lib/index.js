const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const os = require('os');
const crypto = require('crypto');

// Cache for the executable path
let cachedExecPath = null;

// Determine the executable path based on the platform
const getExecutablePath = () => {
  // Return cached path if available
  if (cachedExecPath) {
    return cachedExecPath;
  }

  const platform = os.platform();
  const possibleLocations = [
    // Standard locations
    path.join(__dirname, '..', 'build', 'Release', platform === 'win32' ? 'aho_corasick_gpu.exe' : 'aho_corasick_gpu'),
    path.join(__dirname, '..', 'build', platform === 'win32' ? 'aho_corasick_gpu.exe' : 'aho_corasick_gpu'),
    // Alternative locations
    path.join(__dirname, '..', 'build', 'Debug', platform === 'win32' ? 'aho_corasick_gpu.exe' : 'aho_corasick_gpu'),
    path.join(__dirname, '..', 'build', 'aho_corasick_gpu', 'Release', platform === 'win32' ? 'aho_corasick_gpu.exe' : 'aho_corasick_gpu'),
    path.join(__dirname, '..', 'build', 'aho_corasick_gpu', 'Debug', platform === 'win32' ? 'aho_corasick_gpu.exe' : 'aho_corasick_gpu')
  ];
  
  for (const loc of possibleLocations) {
    if (fs.existsSync(loc)) {
      cachedExecPath = loc;
      return loc;
    }
  }
  
  throw new Error(`Executable not found in any of the expected locations. Please build the project first.`);
};

/**
 * Find pattern matches in the given text using GPU-accelerated Aho-Corasick algorithm
 * @param {string} text - The text to search in
 * @param {string[]} patterns - Array of patterns to search for
 * @returns {Promise<Array<{pattern: string, count: number}>>} Array of matches with counts
 */
async function findMatches(text, patterns) {
  if (!text || typeof text !== 'string') {
    throw new Error('Text must be a non-empty string');
  }
  if (!Array.isArray(patterns) || patterns.length === 0) {
    throw new Error('Patterns must be a non-empty array of strings');
  }
  if (!patterns.every(p => typeof p === 'string' && p.length > 0)) {
    throw new Error('All patterns must be non-empty strings');
  }

  return new Promise((resolve, reject) => {
    try {
      // Get the executable path
      const execPath = getExecutablePath();
      
      // Create temporary files for input and output
      const tempDir = os.tmpdir();
      const tempId = crypto.randomBytes(16).toString('hex');
      const textFile = path.join(tempDir, `text_${tempId}.txt`);
      const patternsFile = path.join(tempDir, `patterns_${tempId}.txt`);
      const outputFile = path.join(tempDir, `output_${tempId}.json`);

      // Write text and patterns to temporary files
      fs.writeFileSync(textFile, text);
      fs.writeFileSync(patternsFile, patterns.join('\n'));

      // Spawn the process
      const process = spawn(execPath, [
        '--text', textFile,
        '--patterns', patternsFile,
        '--output', outputFile,
        '--json'
      ]);

      let stderr = '';

      process.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      process.on('close', (code) => {
        // Clean up temp files
        try {
          fs.unlinkSync(textFile);
          fs.unlinkSync(patternsFile);
        } catch (err) {
          console.error('Error cleaning up temporary files:', err);
        }

        if (code !== 0) {
          reject(new Error(`Process exited with code ${code}: ${stderr}`));
          return;
        }

        try {
          // Read and parse the output file
          const output = fs.readFileSync(outputFile, 'utf8');
          fs.unlinkSync(outputFile);
          
          const results = JSON.parse(output);
          
          // Format the results to match the expected output
          const formattedResults = patterns.map(pattern => {
            const match = results.find(r => r.pattern === pattern);
            return {
              pattern,
              count: match ? match.count : 0
            };
          });
          
          resolve(formattedResults);
        } catch (err) {
          reject(new Error(`Error processing results: ${err.message}`));
        }
      });

      process.on('error', (err) => {
        reject(new Error(`Failed to start process: ${err.message}`));
      });
    } catch (err) {
      reject(err);
    }
  });
}

/**
 * Process a large file in chunks using GPU-accelerated Aho-Corasick algorithm
 * @param {string} filePath - Path to the file to process
 * @param {string[]} patterns - Array of patterns to search for
 * @param {Object} options - Options for processing
 * @param {number} options.chunkSize - Size of each chunk in bytes (default: 64MB)
 * @param {function} options.onProgress - Callback for progress updates
 * @returns {Promise<Array<{pattern: string, count: number}>>} Array of matches with counts
 */
async function processFile(filePath, patterns, options = {}) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }
  
  // Use larger chunks by default (64MB instead of 10MB)
  const chunkSize = options.chunkSize || 64 * 1024 * 1024;
  const onProgress = options.onProgress || (() => {});
  
  try {
    // Get the executable path once
    const execPath = getExecutablePath();
    
    // Process the file directly with the executable
    return new Promise((resolve, reject) => {
      const tempId = crypto.randomBytes(16).toString('hex');
      const patternsFile = path.join(os.tmpdir(), `patterns_${tempId}.txt`);
      const outputFile = path.join(os.tmpdir(), `output_${tempId}.json`);
      
      // Write patterns to temporary file
      fs.writeFileSync(patternsFile, patterns.join('\n'));
      
      // Spawn the process with the file path directly
      const process = spawn(execPath, [
        '--text', filePath,
        '--patterns', patternsFile,
        '--output', outputFile,
        '--json',
        '--chunk-size', Math.floor(chunkSize / (1024 * 1024)) // Convert to MB
      ]);
      
      let stderr = '';
      let lastProgress = 0;
      
      process.stdout.on('data', (data) => {
        const output = data.toString();
        // Try to extract progress information
        const progressMatch = output.match(/Processing chunk (\d+)\/(\d+)/);
        if (progressMatch) {
          const current = parseInt(progressMatch[1]);
          const total = parseInt(progressMatch[2]);
          const percentage = (current / total) * 100;
          if (percentage > lastProgress + 5) { // Report every 5% change
            lastProgress = percentage;
            onProgress({
              processedChunks: current,
              totalChunks: total,
              percentage
            });
          }
        }
      });
      
      process.stderr.on('data', (data) => {
        stderr += data.toString();
      });
      
      process.on('close', (code) => {
        // Clean up temp file
        try {
          fs.unlinkSync(patternsFile);
        } catch (err) {
          console.error('Error cleaning up temporary files:', err);
        }
        
        if (code !== 0) {
          reject(new Error(`Process exited with code ${code}: ${stderr}`));
          return;
        }
        
        try {
          // Read and parse the output file
          const output = fs.readFileSync(outputFile, 'utf8');
          fs.unlinkSync(outputFile);
          
          const results = JSON.parse(output);
          
          // Format the results to match the expected output
          const formattedResults = patterns.map(pattern => {
            const match = results.find(r => r.pattern === pattern);
            return {
              pattern,
              count: match ? match.count : 0
            };
          });
          
          resolve(formattedResults);
        } catch (err) {
          reject(new Error(`Error processing results: ${err.message}`));
        }
      });
      
      process.on('error', (err) => {
        reject(new Error(`Failed to start process: ${err.message}`));
      });
    });
  } catch (err) {
    throw err;
  }
}

// Export the module functions
module.exports = {
  findMatches,
  processFile
};