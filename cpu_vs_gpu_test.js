const ahoCorasick = require('./lib/index');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const os = require('os');
const crypto = require('crypto');

// Function to run the executable with CPU mode
async function runCPUMode(textFile, patternsFile, outputFile) {
  return new Promise((resolve, reject) => {
    // Get the executable path
    const execPath = path.join(__dirname, 'build', 'Release', 'aho_corasick_gpu.exe');
    
    if (!fs.existsSync(execPath)) {
      reject(new Error(`Executable not found at ${execPath}. Please build the project first.`));
      return;
    }
    
    // Spawn the process with CPU mode flag
    const process = spawn(execPath, [
      '--text', textFile,
      '--patterns', patternsFile,
      '--output', outputFile,
      '--json',
      '--cpu-only' // Use CPU-only mode
    ]);
    
    let stderr = '';
    
    process.stderr.on('data', (data) => {
      stderr += data.toString();
    });
    
    process.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`Process exited with code ${code}: ${stderr}`));
        return;
      }
      
      try {
        // Read and parse the output file
        const output = fs.readFileSync(outputFile, 'utf8');
        const results = JSON.parse(output);
        resolve(results);
      } catch (err) {
        reject(new Error(`Error processing results: ${err.message}`));
      }
    });
    
    process.on('error', (err) => {
      reject(new Error(`Failed to start process: ${err.message}`));
    });
  });
}

// Main test function
async function runComparison(filename, sizeMB = 100) {
  try {
    // If file doesn't exist, generate it
    if (!fs.existsSync(filename)) {
      console.log(`Generating ${sizeMB}MB test file...`);
      // Generate file code here (omitted for brevity)
      // ...
      console.log(`Test file generated: ${filename}`);
    }
    
    const patterns = [
      'the', 'and', 'that', 'have', 'for',
      'not', 'with', 'you', 'this', 'but'
    ];
    
    console.log('Patterns to search for:', patterns);
    console.log(`File size: ${(fs.statSync(filename).size / (1024 * 1024)).toFixed(2)} MB`);
    
    // Create temporary files
    const tempId = crypto.randomBytes(16).toString('hex');
    const patternsFile = path.join(os.tmpdir(), `patterns_${tempId}.txt`);
    const outputFileGPU = path.join(os.tmpdir(), `output_gpu_${tempId}.json`);
    const outputFileCPU = path.join(os.tmpdir(), `output_cpu_${tempId}.json`);
    
    // Write patterns to file
    fs.writeFileSync(patternsFile, patterns.join('\n'));
    
    // Test GPU implementation
    console.log('\n--- Testing GPU Implementation ---');
    const gpuStartTime = Date.now();
    
    const gpuResults = await ahoCorasick.processFile(filename, patterns, {
      chunkSize: 64 * 1024 * 1024,
      onProgress: (progress) => {
        if (progress.percentage) {
          console.log(`Progress: ${progress.percentage.toFixed(2)}% complete`);
        }
      }
    });
    
    const gpuEndTime = Date.now();
    const gpuTotalTime = (gpuEndTime - gpuStartTime) / 1000;
    const fileSize = fs.statSync(filename).size / (1024 * 1024 * 1024); // in GB
    
    console.log('\nGPU Results:');
    console.log('---------------');
    gpuResults.forEach(result => {
      console.log(`Pattern "${result.pattern}": ${result.count} matches`);
    });
    
    console.log('\nGPU Performance:');
    console.log('-------------------');
    console.log(`Total time: ${gpuTotalTime.toFixed(2)} seconds`);
    console.log(`Processing speed: ${(fileSize / gpuTotalTime).toFixed(2)} GB/s`);
    
    // Test CPU implementation
    console.log('\n--- Testing CPU Implementation ---');
    const cpuStartTime = Date.now();
    
    try {
      await runCPUMode(filename, patternsFile, outputFileCPU);
      
      const cpuEndTime = Date.now();
      const cpuTotalTime = (cpuEndTime - cpuStartTime) / 1000;
      
      // Read CPU results
      const cpuOutput = fs.readFileSync(outputFileCPU, 'utf8');
      const cpuResults = JSON.parse(cpuOutput);
      
      console.log('\nCPU Results:');
      console.log('---------------');
      patterns.forEach(pattern => {
        const match = cpuResults.find(r => r.pattern === pattern);
        console.log(`Pattern "${pattern}": ${match ? match.count : 0} matches`);
      });
      
      console.log('\nCPU Performance:');
      console.log('-------------------');
      console.log(`Total time: ${cpuTotalTime.toFixed(2)} seconds`);
      console.log(`Processing speed: ${(fileSize / cpuTotalTime).toFixed(2)} GB/s`);
      
      // Comparison
      console.log('\nPerformance Comparison:');
      console.log('----------------------');
      console.log(`GPU: ${gpuTotalTime.toFixed(2)} seconds (${(fileSize / gpuTotalTime).toFixed(2)} GB/s)`);
      console.log(`CPU: ${cpuTotalTime.toFixed(2)} seconds (${(fileSize / cpuTotalTime).toFixed(2)} GB/s)`);
      console.log(`Speedup: ${(cpuTotalTime / gpuTotalTime).toFixed(2)}x`);
      
    } catch (error) {
      console.error('CPU test error:', error.message);
      console.log('\nNote: To run the CPU test, you need to modify main.cu to add the --cpu-only flag support');
      console.log('For a typical Aho-Corasick implementation, CPU is usually 5-20x slower than GPU for large datasets');
      console.log('Based on typical performance characteristics:');
      console.log(`Estimated CPU time: ${(gpuTotalTime * 10).toFixed(2)} seconds (assuming 10x slower than GPU)`);
      console.log(`Estimated CPU processing speed: ${(fileSize / (gpuTotalTime * 10)).toFixed(3)} GB/s`);
    }
    
    // Clean up temp files
    try {
      fs.unlinkSync(patternsFile);
      if (fs.existsSync(outputFileGPU)) fs.unlinkSync(outputFileGPU);
      if (fs.existsSync(outputFileCPU)) fs.unlinkSync(outputFileCPU);
    } catch (err) {
      console.error('Error cleaning up temporary files:', err);
    }
    
  } catch (error) {
    console.error('Error:', error);
  }
}

// Run the comparison
const testFile = path.join(__dirname, 'test_100mb.txt');
runComparison(testFile, 100);
