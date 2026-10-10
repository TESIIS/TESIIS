// Cross-platform production-build harness for machines without Docker.
// CI continues to exercise the Nginx/Compose deployment separately.
import http from 'node:http';
import { createReadStream } from 'node:fs';
import { access, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { createGzip } from 'node:zlib';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const build = path.join(root, 'flutter_codefest', 'build', 'web');
await access(path.join(build, 'offline-manifest.js'));
let dart = process.env.DART_EXECUTABLE ?? 'dart';
if (process.platform === 'win32' && !process.env.DART_EXECUTABLE) {
  search: for (const directory of (process.env.PATH ?? '').split(path.delimiter)) {
    for (const relative of ['dart.exe', 'cache/dart-sdk/bin/dart.exe']) {
      const candidate = path.join(directory.replace(/^"|"$/g, ''), relative);
      try { await access(candidate); dart = candidate; break search; } catch (_) {}
    }
  }
}
const backend = spawn(dart, ['run', 'bin/server.dart', '18081'], {
  cwd: path.join(root, 'server'), stdio: 'inherit',
  env: {...process.env, NFA_POINT_FILE_URL: 'http://127.0.0.1:1/unavailable', ALERT_FEED_URL: 'http://127.0.0.1:1/unavailable', TDX_CLIENT_ID: '', TDX_CLIENT_SECRET: ''},
});
const types = {'.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.otf': 'font/otf', '.png': 'image/png', '.ico': 'image/x-icon', '.svg': 'image/svg+xml', '.css': 'text/css'};
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/healthz' || url.pathname.startsWith('/api/')) {
      const proxy = http.request({hostname: '127.0.0.1', port: 18081, path: req.url, method: req.method}, (upstream) => {
        res.writeHead(upstream.statusCode, upstream.headers); upstream.pipe(res);
      });
      proxy.on('error', () => { res.writeHead(503); res.end('API starting'); }); req.pipe(proxy); return;
    }
    if (url.pathname === '/app') { res.writeHead(302, {location: '/app/'}); res.end(); return; }
    const app = url.pathname.startsWith('/app/');
    const directory = app ? build : path.join(root, 'flutter_codefest', 'landing');
    const relative = decodeURIComponent(app ? url.pathname.slice(5) : url.pathname.slice(1));
    let file = path.resolve(directory, relative || 'index.html');
    if (!file.startsWith(directory + path.sep)) { res.writeHead(400); res.end(); return; }
    try { if ((await stat(file)).isDirectory()) file = path.join(file, 'index.html'); await access(file); }
    catch (_) { if (!app || path.extname(relative)) { res.writeHead(404); res.end(); return; } file = path.join(build, 'index.html'); }
    const type = types[path.extname(file)] ?? 'application/octet-stream';
    const gzip = /gzip/.test(req.headers['accept-encoding'] ?? '') && /javascript|json|text|font|wasm/.test(type);
    res.writeHead(200, {'content-type': type, 'cache-control': 'no-cache', ...(gzip ? {'content-encoding': 'gzip'} : {})});
    const stream = createReadStream(file);
    stream.on('error', () => res.destroy());
    if (gzip) stream.pipe(createGzip()).pipe(res); else stream.pipe(res);
  } catch (_) { res.writeHead(500); res.end(); }
});
server.listen(18088, '127.0.0.1');
function stop() {
  if (process.platform === 'win32') spawn('taskkill', ['/pid', String(backend.pid), '/T', '/F'], {stdio: 'ignore'});
  else backend.kill('SIGTERM');
  server.close(() => process.exit());
}
process.on('SIGINT', stop); process.on('SIGTERM', stop);
backend.on('error', (error) => { console.error(error); stop(); });
