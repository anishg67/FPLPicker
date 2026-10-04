// Local dev server: serves the static files and the /api/fpl proxy, so the app
// can be run with `npm run dev` without installing anything.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import handler from './api/fpl.js';

const root = fileURLToPath(new URL('.', import.meta.url));
const port = Number(process.env.PORT) || 4321;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
};

createServer(async (request, response) => {
  const url = new URL(request.url, `http://localhost:${port}`);

  if (url.pathname === '/api/fpl') {
    // Shim the two response helpers the serverless function uses.
    response.status = (code) => { response.statusCode = code; return response; };
    response.json = (body) => {
      response.setHeader('Content-Type', 'application/json; charset=utf-8');
      response.end(JSON.stringify(body));
    };
    response.send = (body) => response.end(body);
    await handler(request, response);
    return;
  }

  const relative = url.pathname === '/' ? 'index.html' : normalize(url.pathname).replace(/^(\.\.[/\\])+/, '').replace(/^[/\\]+/, '');
  try {
    const file = await readFile(join(root, relative));
    response.setHeader('Content-Type', TYPES[extname(relative)] || 'application/octet-stream');
    response.end(file);
  } catch {
    response.statusCode = 404;
    response.end('Not found');
  }
}).listen(port, () => {
  console.log(`Squad XI running at http://localhost:${port}`);
});
