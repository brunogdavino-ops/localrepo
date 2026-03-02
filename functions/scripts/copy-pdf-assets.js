const fs = require('node:fs');
const path = require('node:path');

const filesToCopy = [
  {
    from: path.resolve(__dirname, '..', 'src', 'pdf', 'templates', 'audit-report.html'),
    to: path.resolve(__dirname, '..', 'lib', 'pdf', 'templates', 'audit-report.html')
  },
  {
    from: path.resolve(__dirname, '..', 'src', 'pdf', 'templates', 'logo-artezi.png'),
    to: path.resolve(__dirname, '..', 'lib', 'pdf', 'templates', 'logo-artezi.png')
  }
];

for (const file of filesToCopy) {
  fs.mkdirSync(path.dirname(file.to), { recursive: true });
  fs.copyFileSync(file.from, file.to);
}
