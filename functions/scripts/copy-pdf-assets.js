const fs = require('node:fs');
const path = require('node:path');

function copyRecursive(sourceDir, targetDir) {
  fs.mkdirSync(targetDir, { recursive: true });
  const entries = fs.readdirSync(sourceDir, { withFileTypes: true });
  for (const entry of entries) {
    const from = path.join(sourceDir, entry.name);
    const to = path.join(targetDir, entry.name);
    if (entry.isDirectory()) {
      copyRecursive(from, to);
    } else {
      fs.copyFileSync(from, to);
    }
  }
}

const templateSourceDir = path.resolve(__dirname, '..', 'src', 'pdf', 'templates');
const templateTargetDir = path.resolve(__dirname, '..', 'lib', 'pdf', 'templates');
copyRecursive(templateSourceDir, templateTargetDir);
