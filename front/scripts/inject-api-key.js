const fs = require('fs');
const path = require('path');

// Read the API key from environment variable
const apiKey =
  process.env.INNER_CALLS_KEY ||
  process.env.BOT_API_KEY ||
  process.env.API_KEY ||
  '';

if (!apiKey) {
  console.warn('Warning: INNER_CALLS_KEY/BOT_API_KEY/API_KEY is not set.');
  console.warn('The app will work but API calls may fail.');
  console.warn('To set it locally, run: export INNER_CALLS_KEY=your_key_here (Linux/Mac) or set INNER_CALLS_KEY=your_key_here (Windows)');
}

// Path to the built index.html
// This script should be run from the front/ directory
const indexPath = path.join(__dirname, '../build/web/index.html');

// Check if the file exists
if (!fs.existsSync(indexPath)) {
  console.error('Error: index.html not found at:', indexPath);
  console.error('Make sure you run this script from the front/ directory after building.');
  process.exit(1);
}

// Read the HTML file
let html = fs.readFileSync(indexPath, 'utf8');

// Check if placeholder exists
if (!html.includes('{{API_KEY}}')) {
  console.warn('Warning: {{API_KEY}} placeholder not found in index.html. It may have already been replaced.');
}

// Replace the placeholder with the actual API key
html = html.replace(/\{\{API_KEY\}\}/g, apiKey);

// Write back to the file
fs.writeFileSync(indexPath, html, 'utf8');

if (apiKey) {
  console.log('✓ API key injected into index.html');
} else {
  console.log('✓ index.html processed (API key was empty)');
}

