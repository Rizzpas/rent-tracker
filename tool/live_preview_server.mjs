// Local Flutter preview with automatic Hot Reload after Dart files are saved.
// Start: node tool/live_preview_server.mjs
// Stop:  node tool/live_preview_server.mjs --stop
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, watch } from 'node:fs';
import { createHash } from 'node:crypto';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceId = createHash('sha256').update(projectRoot.toLowerCase()).digest('hex').slice(0, 12);
const controlPath = process.platform === 'win32'
  ? `\\\\.\\pipe\\bahay-preview-${workspaceId}`
  : path.join(os.tmpdir(), `bahay-preview-${workspaceId}.sock`);
const args = process.argv.slice(2);
const portArg = args.find((arg) => arg.startsWith('--port='));
const port = portArg ? Number(portArg.split('=')[1]) : 7357;
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Choose a port from 1024 to 65535.');
const url = `http://127.0.0.1:${port}`;

function control(command) {
  return new Promise((resolve, reject) => {
    const socket = net.connect(controlPath);
    let buffer = '';
    socket.setTimeout(45000, () => socket.destroy(new Error('Preview command timed out.')));
    socket.once('connect', () => socket.write(`${command}\n`));
    socket.on('data', (chunk) => {
      buffer += chunk;
      if (buffer.includes('\n')) { socket.end(); resolve(JSON.parse(buffer.split('\n')[0])); }
    });
    socket.once('error', reject);
  });
}

const action = args.find((arg) => ['--stop', '--status', '--reload', '--restart'].includes(arg));
if (action) {
  try {
    const result = await control(action.substring(2));
    if (action === '--stop' && result.url) {
      const stoppingPort = Number(new URL(result.url).port);
      for (let attempt = 0; attempt < 30 && await portInUse(stoppingPort); attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 400));
      }
    }
    console.log(result.message ?? JSON.stringify(result));
    process.exitCode = result.ok === false ? 1 : 0;
  } catch (error) {
    if (['ENOENT', 'ECONNREFUSED'].includes(error.code)) {
      console.log('No standalone live preview is running.');
      process.exitCode = action === '--stop' ? 0 : 1;
    } else { throw error; }
  }
} else {
  const existing = await control('status').catch(() => null);
  if (existing) {
    console.log(`Live preview is already running at ${existing.url}`);
  } else {
    await start();
  }
}

async function start() {
  if (await portInUse(port)) throw new Error(`Port ${port} is in use. Stop the existing VS Code debug session or choose --port=7359.`);
  const sdk = process.env.FLUTTER_ROOT || path.join(os.homedir(), '.cache', 'rent_tracker_tools', 'flutter');
  const executable = path.join(sdk, 'bin', process.platform === 'win32' ? 'flutter.bat' : 'flutter');
  if (!existsSync(executable)) throw new Error(`Flutter SDK was not found at ${sdk}. Set FLUTTER_ROOT to its folder.`);
  if (!existsSync(path.join(projectRoot, 'web', 'sqlite3.wasm'))) throw new Error('The preview SQLite asset web/sqlite3.wasm is missing.');
  mkdirSync(path.join(projectRoot, '.dart_tool', 'live_preview'), { recursive: true });

  let appId, ready = false, stopping = false, busy = false, queued = false, reloadTimer;
  let requestId = 1;
  const requests = new Map();
  const watchers = [];
  const log = (message) => console.log(`[${new Date().toLocaleTimeString()}] ${message}`);
  const flutterArgs = ['run', '--machine', '--no-pub', '-d', 'chrome', '-t', 'tool/live_preview.dart',
    `--web-port=${port}`, '--web-hostname=127.0.0.1', '--no-web-resources-cdn'];
  const child = process.platform === 'win32'
    ? spawn('cmd.exe', ['/d', '/s', '/c', `""${executable}" ${flutterArgs.join(' ')}"`], {
        cwd: projectRoot, windowsVerbatimArguments: true, windowsHide: true,
        env: { ...process.env, DEBUG: '' }, stdio: ['pipe', 'pipe', 'pipe'],
      })
    : spawn(executable, flutterArgs, { cwd: projectRoot, stdio: ['pipe', 'pipe', 'pipe'] });

  function request(method, params) {
    return new Promise((resolve, reject) => {
      const id = requestId++;
      const timeout = setTimeout(() => { requests.delete(id); reject(new Error(`${method} timed out.`)); }, 40000);
      requests.set(id, {
        resolve: (result) => { clearTimeout(timeout); resolve(result); },
        reject: (error) => { clearTimeout(timeout); reject(error); },
      });
      child.stdin.write(`${JSON.stringify([{ id, method, params }])}\n`);
    });
  }

  async function reload(fullRestart = false) {
    if (!ready || busy) { queued = true; return { ok: false, message: 'Preview is starting or reloading; saved changes are queued.' }; }
    busy = true;
    queued = false;
    log(fullRestart ? 'Hot Restart…' : 'Saved Dart file → Hot Reload…');
    try {
      const result = await request('app.restart', { appId, fullRestart, pause: false, reason: 'save', debounce: true });
      if (result?.code !== 0) throw new Error(result?.message || 'Reload failed. Fix the compiler error and save again.');
      const message = fullRestart ? 'Hot Restart complete.' : 'Hot Reload complete.';
      log(message);
      return { ok: true, message };
    } catch (error) {
      log(error.message);
      return { ok: false, message: error.message };
    } finally {
      busy = false;
      if (queued) { clearTimeout(reloadTimer); reloadTimer = setTimeout(() => void reload(), 400); }
    }
  }

  function handleLine(line) {
    let events;
    try { events = JSON.parse(line); } catch { if (line.trim()) log(line); return; }
    if (!Array.isArray(events)) return;
    for (const event of events) {
      if (event.id !== undefined && requests.has(event.id)) {
        const pending = requests.get(event.id);
        requests.delete(event.id);
        event.error ? pending.reject(new Error(JSON.stringify(event.error))) : pending.resolve(event.result);
      }
      if (event.event === 'app.start') appId = event.params.appId;
      if (event.event === 'app.started') {
        ready = true;
        log(`READY: ${url} — edit a Dart file and save to update the UI.`);
        if (queued) void reload();
      }
      if (event.event === 'app.log') log(event.params.log);
      if (event.event === 'app.progress' && event.params.message) log(event.params.message);
      if (event.event === 'app.warning') log(event.params.warning);
    }
  }
  createInterface({ input: child.stdout }).on('line', handleLine);
  createInterface({ input: child.stderr }).on('line', (line) => log(line));
  child.once('error', (error) => { log(error.message); void shutdown(); });
  child.once('exit', (code) => {
    log(`Flutter preview stopped (${code ?? 'signal'}).`);
    for (const pending of requests.values()) pending.reject(new Error('Flutter stopped.'));
    requests.clear();
    cleanup();
    process.exit(stopping ? 0 : code ?? 0);
  });

  const server = net.createServer((socket) => {
    socket.once('data', async (buffer) => {
      const command = buffer.toString().trim();
      if (command === 'stop') {
        socket.end(`${JSON.stringify({ ok: true, url, message: 'Stopping the live preview.' })}\n`);
        void shutdown();
      } else if (command === 'reload' || command === 'restart') {
        socket.end(`${JSON.stringify(await reload(command === 'restart'))}\n`);
      } else {
        socket.end(`${JSON.stringify({ ok: true, ready, url, message: `${ready ? 'Ready' : 'Starting'}: ${url}` })}\n`);
      }
    });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(controlPath, resolve); });
  for (const directory of ['lib', 'tool']) {
    watchers.push(watch(path.join(projectRoot, directory), { recursive: true }, (_, filename) => {
      if (!filename?.endsWith('.dart')) return;
      clearTimeout(reloadTimer);
      reloadTimer = setTimeout(() => void reload(), 600);
    }));
  }
  function cleanup() {
    clearTimeout(reloadTimer);
    for (const watcher of watchers) watcher.close();
    if (server.listening) server.close();
  }
  async function shutdown() {
    if (stopping) return;
    stopping = true;
    cleanup();
    if (appId) request('app.stop', { appId }).catch(() => {});
    else child.stdin.end();
    setTimeout(() => {
      if (process.platform === 'win32') spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      else child.kill();
      setTimeout(() => process.exit(0), 1000);
    }, 6000).unref();
  }
  process.once('SIGINT', () => void shutdown());
  process.once('SIGTERM', () => void shutdown());
  log(`Starting live Flutter UI at ${url}`);
  log('Chrome will open automatically. Changes to saved lib/ and tool/ Dart files trigger Hot Reload.');
}

function portInUse(value) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port: value });
    socket.once('connect', () => { socket.destroy(); resolve(true); });
    socket.once('error', () => resolve(false));
  });
}
