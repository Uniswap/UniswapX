const esbuild = require('esbuild');
const fs = require('fs');
const path = require('path');

// Ensure dist directory exists
const distDir = path.join(__dirname, 'dist');
if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir, { recursive: true });
}

// Build all TypeScript files in src directory
const srcDir = path.join(__dirname, 'src');
const files = fs.readdirSync(srcDir).filter(file => file.endsWith('.ts'));

files.forEach(file => {
  const inputFile = path.join(srcDir, file);
  const outputFile = path.join(distDir, file.replace('.ts', '.js'));

  esbuild.buildSync({
    entryPoints: [inputFile],
    bundle: true,
    platform: 'node',
    target: 'node18',
    outfile: outputFile,
    format: 'cjs',
    external: [],
  });

  console.log(`Built ${file} -> ${path.basename(outputFile)}`);
});

console.log('Build complete!');
