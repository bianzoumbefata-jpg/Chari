const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.m4a': 'audio/mp4',
  '.webm': 'audio/webm'
};

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    });
    res.end();
    return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('405 Méthode non autorisée');
    return;
  }

  let file = req.url.split('?')[0];
  try {
    file = decodeURIComponent(file);
  } catch (e) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('400 URL invalide');
    return;
  }

  // Sécurité : Interdiction formelle du Path Traversal et fichiers cachés (.git, .env...)
  if (file.includes('..') || file.includes('\\') || /(^|\/)\./.test(file)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('403 Accès interdit');
    return;
  }

  if (file === '/' || file === '') file = '/index.html';

  const rootDir = path.resolve(__dirname);
  const wwwDir = path.resolve(__dirname, 'www');

  // Fichiers sensibles à la racine strictement interdits au public
  const SENSITIVE_ROOT = ['server.js', 'package.json', 'package-lock.json', 'capacitor.config.json', 'capacitor.config.ts', 'tsconfig.json'];
  const baseName = path.basename(file).toLowerCase();
  if (SENSITIVE_ROOT.includes(baseName)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('403 Accès interdit');
    return;
  }

  // Recherche dans www/ en priorité
  let fullPath = path.resolve(wwwDir, '.' + file);
  if (!fs.existsSync(fullPath)) {
    // Si absent de www/, autoriser uniquement le fichier HTML racine de secours
    if (baseName === 'chari · rencontres au tchad.html' || baseName === 'index.html') {
      fullPath = path.resolve(rootDir, '.' + file);
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Non trouvé');
      return;
    }
  }

  // Double vérification de confinement
  if (!fullPath.startsWith(rootDir)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('403 Accès interdit');
    return;
  }

  fs.stat(fullPath, (statErr, stats) => {
    if (statErr || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Non trouvé');
      return;
    }

    const ext = path.extname(fullPath).toLowerCase();
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': ext === '.html' ? 'no-cache, must-revalidate' : 'public, max-age=3600',
      'Access-Control-Allow-Origin': '*',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'SAMEORIGIN',
      'Referrer-Policy': 'strict-origin-when-cross-origin'
    });

    if (req.method === 'HEAD') {
      res.end();
      return;
    }

    fs.createReadStream(fullPath).pipe(res);
  });
});

server.listen(PORT, () => {
  console.log(`\n========================================`);
  console.log(`  Chari - Serveur Web Actif`);
  console.log(`  URL locale : http://localhost:${PORT}`);
  console.log(`========================================\n`);
});
