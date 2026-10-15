const http = require('http');
const fs = require('fs');
const path = require('path');

const root = __dirname;
http.createServer((req, res) => {
  const requested = req.url === '/' ? '/product.html' : req.url;
  const file = path.join(root, path.normalize(requested).replace(/^([.][.][\\/])+/, ''));
  if (!file.startsWith(root)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }
  fs.readFile(file, (error, data) => {
    if (error) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(data);
  });
}).listen(4173, '127.0.0.1', () => console.log('UI prototype: http://127.0.0.1:4173'));
